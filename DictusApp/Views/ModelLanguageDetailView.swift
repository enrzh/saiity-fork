// DictusApp/Views/ModelLanguageDetailView.swift
// Per-model supported-languages detail sheet (issue #240).
import SwiftUI
import SyllivraKernel

/// Curated language-support detail for one model, presented as a sheet from
/// the ⓘ affordance on a model card.
///
/// WHY a sheet instead of an inline list on the card (#240 locked decision):
/// Model cards are already dense (badges, states, overflow menu).
/// A dedicated scrollable sheet leaves room for per-language quality notes
/// and stays safe at large Dynamic Type sizes.
///
/// CONTENT (top to bottom):
/// - one-line coverage summary ("About 99 languages", "25 European languages")
/// - curated main languages, the four Dictus-tested ones first, with
///   per-tier quality notes where warranted (e.g. Chinese on small models)
/// - Whisper: the complete tokenizer language list grouped by published
///   quality tier (design round, grounded in OpenAI's large-v3 FLEURS
///   results), each tier as flowing comma-separated text, plus a caveat
///   that tiers were measured on the large models
/// - Parakeet: the full remaining documented list ("Also supported"); the
///   25-language summary + exhaustive list convey the European-only limit
struct ModelLanguageDetailView: View {
    let model: ModelInfo

    @Environment(\.dismiss) private var dismiss

    /// Convenience accessor for the curated metadata.
    private var support: ModelLanguageSupport { model.languageSupport }

    var body: some View {
        NavigationStack {
            List {
                // Coverage summary
                Section {
                    Text(model.localizedDescription)
                    LabeledContent("Download size", value: model.sizeLabel)
                    Text(support.coverage.localizedSummary)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("About this model")
                } footer: {
                    Text("Language coverage depends on the model. Try your own phrases before choosing.")
                }

                // Keep the most useful languages at the top, with notes in the
                // row rather than as a separate color-only treatment.
                Section {
                    ForEach(languageRows, id: \.code) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ModelLanguageSupport.localizedLanguageName(for: entry.code))
                            if let note = entry.note {
                                Label(note.localizedText, systemImage: noteSymbol(for: note))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Main languages")
                }

                // Whisper: complete tokenizer language list grouped by
                // published quality tier. Each language gets a native row so
                // VoiceOver and Dynamic Type can scan the list predictably.
                ForEach(Array(support.tierGroups.enumerated()), id: \.offset) { index, group in
                    Section {
                        ForEach(languageRows(for: group), id: \.self) { language in
                            Label(language, systemImage: qualitySymbol(for: group.tier))
                                .foregroundStyle(.primary)
                        }
                    } header: {
                        Text(localizedTierHeader(for: group.tier))
                    } footer: {
                        // Ground the tiers honestly: numbers come from the
                        // large models; the small ones degrade further.
                        if index == support.tierGroups.count - 1 {
                            Text("Upstream large-v3 FLEURS reference. These tiers are not measurements of this model export or this phone.")
                        }
                    }
                }

                // Parakeet: finite documented list — spell out the rest.
                // Together with the "25 European languages" summary this
                // conveys the European-only limit (design round dropped the
                // extra warning row as redundant).
                if !support.additionalCodes.isEmpty {
                    Section {
                        ForEach(additionalLanguageRows, id: \.self) { language in
                            Text(language)
                        }
                    } header: {
                        Text("Also supported")
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle(model.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityAddTraits(.isModal)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityLabel("Close language support")
                }
            }
        }
    }

    private var languageRows: [ModelLanguageSupport.Entry] {
        support.highlights
    }

    private var additionalLanguageRows: [String] {
        localizedNames(for: support.additionalCodes)
    }

    private func languageRows(for group: ModelLanguageSupport.TierGroup) -> [String] {
        let highlighted = Set(support.highlights.map(\.code))
        return localizedNames(for: group.codes.filter { !highlighted.contains($0) })
    }

    private func localizedNames(for codes: [String]) -> [String] {
        codes
            .map { ModelLanguageSupport.localizedLanguageName(for: $0) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Localized section header for a quality tier.
    private func localizedTierHeader(for tier: ModelLanguageSupport.QualityTier) -> String {
        switch tier {
        case .good:
            return String(localized: "Good quality")
        case .fair:
            return String(localized: "Fair quality")
        case .limited:
            return String(localized: "Limited quality")
        case .unmeasured:
            return String(localized: "No published reference measurement")
        }
    }

    private func noteSymbol(for note: ModelLanguageSupport.QualityNote) -> String {
        switch note {
        case .impreciseUpgradeRecommended:
            return "exclamationmark.triangle"
        case .goodOnThisModel:
            return "checkmark.circle"
        }
    }

    private func qualitySymbol(for tier: ModelLanguageSupport.QualityTier) -> String {
        switch tier {
        case .good:
            return "checkmark.circle"
        case .fair:
            return "circle.lefthalf.filled"
        case .limited:
            return "exclamationmark.circle"
        case .unmeasured:
            return "questionmark.circle"
        }
    }
}

#Preview("Whisper small") {
    ModelLanguageDetailView(model: ModelInfo.redesignCatalog[0])
}
