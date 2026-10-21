"""Prepare smaller generated Syllivra bundle resources; source files stay intact."""
import argparse
import json
from pathlib import Path
import re
import tempfile


def compact_frequency(counts, limit):
    if not isinstance(counts, dict) or type(limit) is not int or limit <= 0:
        raise ValueError("Expected a frequency dictionary and positive word limit")
    if any(not isinstance(word, str) or not word or type(count) is not int or count < 0
           for word, count in counts.items()):
        raise ValueError("Frequency words need nonnegative integer counts")
    if len(counts) <= limit:
        return counts
    cutoff = sorted(counts.values(), reverse=True)[limit - 1]
    # Keep every boundary tie; the runtime remains responsible for its existing cap.
    return {word: count for word, count in counts.items() if count >= cutoff}


def checked_bundle(bundle, source):
    if bundle.is_symlink() or not bundle.is_dir() or bundle.suffix not in [".app", ".appex"]:
        raise ValueError("Destination must be a generated app or extension bundle")
    bundle, source = bundle.resolve(), source.resolve()
    if bundle == source or source in bundle.parents or bundle in source.parents:
        raise ValueError("Source resources and generated bundle must be separate")
    return bundle


def prepare_frequency(source, bundle):
    bundle = checked_bundle(bundle, source)
    core = Path(__file__).resolve().parents[1] / "SyllivraKernel/Sources/SyllivraKernel/FrequencyDictionary.swift"
    match = re.search(r"static let maxWords = ([0-9_]+)", core.read_text())
    if match is None:
        raise ValueError("Could not read the runtime frequency-word limit")
    limit = int(match[1].replace("_", ""))
    for language in ["de", "en", "es", "fr"]:
        name = f"{language}_frequency.json"
        counts = json.loads((source / name).read_text())
        compact = compact_frequency(counts, limit)
        output = bundle / name
        if output.is_symlink():
            raise ValueError("Generated frequency file must not be a symlink")
        encoded = json.dumps(compact, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n"
        output.write_text(encoded, encoding="utf-8")
        print(f"Frequency {language}: {len(counts)} source words; {len(compact)} eligible words; {len(encoded.encode('utf-8'))} bytes")


def self_test():
    counts = {"alpha": 100, "beta": 80, "gamma": 50, "delta": 50, "epsilon": 1}
    assert compact_frequency(counts, 3) == {"alpha": 100, "beta": 80, "gamma": 50, "delta": 50}
    assert compact_frequency(counts, 20) == counts
    assert compact_frequency({}, 3) == {}
    for invalid in [{"word": True}, {"word": -1}, {"word": "1"}, {"": 1}]:
        try:
            compact_frequency(invalid, 3)
        except ValueError:
            pass
        else:
            raise AssertionError("Malformed frequency counts must fail")
    with tempfile.TemporaryDirectory(prefix="syllivra-resource-test-") as temporary:
        root = Path(temporary)
        source = root / "source"
        source.mkdir()
        try:
            checked_bundle(source, source)
        except ValueError:
            pass
        else:
            raise AssertionError("Source directory must never be a generated destination")
        bundle = root / "Probe.app"
        bundle.mkdir()
        assert checked_bundle(bundle, source) == bundle.resolve()
        linked = root / "Linked.app"
        linked.symlink_to(source, target_is_directory=True)
        try:
            checked_bundle(linked, source)
        except ValueError:
            pass
        else:
            raise AssertionError("Symlink destinations must fail")
    print("Frequency cutoff, ties, malformed data and generated-destination checks passed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--kind", choices=["keyboard"])
    parser.add_argument("--source", type=Path)
    parser.add_argument("--bundle", type=Path)
    arguments = parser.parse_args()
    if arguments.self_test:
        self_test()
    elif arguments.kind and arguments.source is not None and arguments.bundle is not None:
        prepare_frequency(arguments.source, arguments.bundle)
    else:
        parser.error("Provide --self-test, or --kind/--source/--bundle")
