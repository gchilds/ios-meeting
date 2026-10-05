import SwiftUI

/// Line-based renderer: `AttributedString(markdown:)` collapses single newlines.
struct MeetingNotesView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let text):
                    Text(inline(text))
                        .font(MusliTheme.title(19))
                        .foregroundStyle(MusliTheme.ink)
                        .padding(.top, 14)
                case .bullet(let text):
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("–")
                            .foregroundStyle(MusliTheme.leaf)
                        Text(inline(text))
                            .foregroundStyle(MusliTheme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .paragraph(let text):
                    Text(inline(text))
                        .foregroundStyle(MusliTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .spacer:
                    Spacer().frame(height: 4)
                }
            }
        }
        .font(.body)
        .lineSpacing(3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private enum Block {
        case heading(String)
        case bullet(String)
        case paragraph(String)
        case spacer
    }

    private var blocks: [Block] {
        markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { line -> Block in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { return .spacer }
                if trimmed.hasPrefix("### ") { return .heading(String(trimmed.dropFirst(4))) }
                if trimmed.hasPrefix("## ") { return .heading(String(trimmed.dropFirst(3))) }
                if trimmed.hasPrefix("# ") { return .heading(String(trimmed.dropFirst(2))) }
                if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                    return .bullet(String(trimmed.dropFirst(2)))
                }
                if let match = trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                    return .bullet(String(trimmed[match.upperBound...]))
                }
                return .paragraph(trimmed)
            }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}
