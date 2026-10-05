import SwiftUI

/// Lightweight markdown display for meeting notes.
/// Apple's `AttributedString(markdown:)` collapses single newlines into spaces,
/// which turns our OpenAI output into one run-on line — so we render by line.
struct MeetingNotesView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let text):
                    Text(inline(text))
                        .font(.title3.weight(.semibold))
                        .padding(.top, 10)
                case .bullet(let text):
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                        Text(inline(text))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .paragraph(let text):
                    Text(inline(text))
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .spacer:
                    Spacer().frame(height: 6)
                }
            }
        }
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
                if trimmed.hasPrefix("### ") {
                    return .heading(String(trimmed.dropFirst(4)))
                }
                if trimmed.hasPrefix("## ") {
                    return .heading(String(trimmed.dropFirst(3)))
                }
                if trimmed.hasPrefix("# ") {
                    return .heading(String(trimmed.dropFirst(2)))
                }
                if trimmed.hasPrefix("- ") {
                    return .bullet(String(trimmed.dropFirst(2)))
                }
                if trimmed.hasPrefix("* ") {
                    return .bullet(String(trimmed.dropFirst(2)))
                }
                if let match = trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                    return .bullet(String(trimmed[match.upperBound...]))
                }
                return .paragraph(trimmed)
            }
    }

    /// Inline **bold** / *italic* only — preserves the rest as plain text.
    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}
