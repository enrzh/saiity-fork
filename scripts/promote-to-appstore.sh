#!/bin/sh
# promote-to-appstore.sh — ship a TestFlight build to the App Store.
#
# Pins the release to the EXACT commit that produced build N (the `build/N`
# tag), never to develop's current tip — so the bits users get are the bits
# that were tested on TestFlight, even if develop has moved on since.
#
# What it does:
#   1. Resolve the `build/N` tag -> commit C and marketing version X.Y.Z.
#   2. Create an ephemeral `release/X.Y.Z` branch at C and open a PR to main.
#   3. Wait for required checks (Build + SwiftLint), then merge without --admin.
#   4. Tag `vX.Y.Z` (annotated) on main + push, create a GitHub Release.
#   5. Back-merge main -> develop (the step that must never be forgotten).
#   6. Print the App Store Connect checklist (the only manual part).
#
# The binary is NOT rebuilt: in App Store Connect you select build N (already
# uploaded from TestFlight) and submit it. This script only moves source +
# tags + the GitHub release.
#
# Usage:
#   scripts/promote-to-appstore.sh 18
#
# See docs/VERSIONING.md and docs/GIT_WORKFLOW.md for the full policy.
set -eu

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO_ROOT"
PB=/usr/libexec/PlistBuddy

BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" != "develop" ]; then
  echo "error: must start on 'develop' (currently on '$BRANCH'). Aborting." >&2
  exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "error: working tree is not clean. Aborting before any ref change." >&2
  git status --short >&2
  exit 1
fi
for tool in git gh "$PB"; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "error: required tool '$tool' is not available." >&2
    exit 1
  }
done

N="${1:-}"
case "$N" in
  ''|*[!0-9]*) echo "usage: scripts/promote-to-appstore.sh <build-number>" >&2; exit 1 ;;
esac

TAG="build/$N"
if ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  git fetch origin --tags --quiet
  git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || {
    echo "error: tag $TAG not found. Was build $N cut with cut-testflight.sh?" >&2; exit 1; }
fi

COMMIT=$(git rev-parse "$TAG^{commit}")
TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT
git show "$TAG:DictusApp/Info.plist" > "$TMP"
VERSION=$($PB -c "Print :CFBundleShortVersionString" "$TMP")
VTAG="v$VERSION"
RELEASE_BRANCH="release/$VERSION"

if git rev-parse -q --verify "refs/tags/$VTAG" >/dev/null; then
  echo "error: tag $VTAG already exists — $VERSION looks already released." >&2; exit 1
fi

echo "→ build      : $N  (tag $TAG)"
echo "→ commit     : $COMMIT"
echo "→ version    : $VERSION  -> will tag $VTAG + GitHub Release"
echo "→ PR         : $RELEASE_BRANCH -> main (merge after CI, no admin override)"
printf "Proceed with the App Store promotion of build %s? [y/N] " "$N"
read -r ANSWER
case "$ANSWER" in [yY]*) : ;; *) echo "Aborted."; exit 1 ;; esac

refuse_conflicting_ref() {
  ref="$1"
  if git rev-parse -q --verify "$ref" >/dev/null; then
    existing=$(git rev-parse "${ref}^{commit}")
    if [ "$existing" != "$COMMIT" ]; then
      echo "error: $ref already points at $existing, not $COMMIT. Refusing to move it." >&2
      exit 1
    fi
  fi
}
refuse_conflicting_ref "refs/heads/$RELEASE_BRANCH"
refuse_conflicting_ref "refs/tags/$VTAG"
remote_release=$(git ls-remote origin "refs/heads/$RELEASE_BRANCH" || true)
if [ -n "$remote_release" ]; then
  remote_commit=$(printf '%s\n' "$remote_release" | awk 'NR==1 { print $1 }')
  if [ "$remote_commit" != "$COMMIT" ]; then
    echo "error: origin/$RELEASE_BRANCH points at $remote_commit, not $COMMIT. Refusing to force-push." >&2
    exit 1
  fi
fi

# --- 1. Ephemeral release branch at the pinned commit -----------------------
if ! git rev-parse -q --verify "refs/heads/$RELEASE_BRANCH" >/dev/null; then
  git branch "$RELEASE_BRANCH" "$COMMIT"
fi
git push origin "$RELEASE_BRANCH"

# --- 2. PR to main ----------------------------------------------------------
PR_URL=$(gh pr create --base main --head "$RELEASE_BRANCH" \
  --title "release: $VTAG (build $N)" \
  --body "Promote TestFlight build $N (\`$TAG\`, commit \`$COMMIT\`) to the App Store. Source-only; binary is promoted in App Store Connect.")
echo "PR: $PR_URL"

# --- 3. Wait for required checks, then admin-merge --------------------------
echo "Waiting for required checks (Build + SwiftLint)…"
gh pr checks "$PR_URL" --watch
gh pr merge "$PR_URL" --merge --delete-branch

# --- 4. Tag + GitHub Release on main ----------------------------------------
git checkout main
git pull origin main --quiet
git tag -a "$VTAG" -m "$VTAG (build $N)"
git push origin "$VTAG"
gh release create "$VTAG" --title "$VTAG" --notes "Build $N. Edit these notes with the user-facing changelog."

# --- 5. Back-merge main -> develop (never forget) ---------------------------
git checkout develop
git pull origin develop --quiet
git merge main --no-edit
git push origin develop

cat <<EOF

✅ Source promoted: $VTAG tagged on main, GitHub Release created, main merged back into develop.

📱 Now finish in App Store Connect (the manual part):
   1. My Apps → Dictus → (create / open) the $VERSION App Store version.
   2. Build section → select build $N (already uploaded from TestFlight).
   3. Fill release notes / screenshots / metadata if not done.
   4. Export compliance: ITSAppUsesNonExemptEncryption → already set in Info.plist.
   5. Submit for Review.
   6. Edit the GitHub Release notes ($VTAG) with the user-facing changelog.
EOF
