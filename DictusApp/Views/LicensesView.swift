import SwiftUI

/// Each shipped dependency gets its own native card and original license text.
struct LicensesView: View {
    private struct Notice: Decodable, Identifiable {
        let name: String
        let source: String
        let text: String
        var id: String { name }
    }
    private static let notices: [Notice] = {
        guard let url = Bundle.main.url(forResource: "OpenSourceNotices", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let notices = try? JSONDecoder().decode([Notice].self, from: data) else { return [] }
        return notices
    }()

    var body: some View {
        List {
            if Self.notices.isEmpty { Text("License notices are unavailable.") }
            ForEach(Self.notices) { notice in
                Section {
                    NoticeCard(notice: notice)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Licenses")
    }

    private struct NoticeCard: View {
        let notice: Notice
        @State private var expanded = false

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Label(notice.name, systemImage: "doc.text").font(.headline)
                if let url = URL(string: notice.source) {
                    Link("Project website", destination: url).font(.subheadline)
                }
                DisclosureGroup("License text", isExpanded: $expanded) {
                    if expanded {
                        Text(notice.text).font(.footnote).foregroundStyle(.secondary)
                            .textSelection(.enabled).padding(.top, 8)
                    }
                }.accessibilityLabel("License for \(notice.name)")
            }
            .padding(.vertical, 8)
        }
    }
}
