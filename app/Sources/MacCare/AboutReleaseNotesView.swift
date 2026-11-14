import SwiftUI

/// Les notes du flux signé restent du texte natif, sélectionnable et défilant avec la page.
struct AboutReleaseNotesView: View {
    let notes: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(notes.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
                Text((try? AttributedString(markdown: paragraph, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(paragraph))
                    .font(AppFont.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .textSelection(.enabled)
    }
}
