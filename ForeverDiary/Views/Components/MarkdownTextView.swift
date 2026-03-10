import SwiftUI

struct MarkdownTextView: View {
    let text: String

    var body: some View {
        if text.isEmpty {
            Text("Nothing written yet.")
                .font(.system(.body, design: .serif))
                .foregroundStyle(Color("textSecondary").opacity(0.6))
        } else {
            Text(Self.parseMarkdown(text))
                .font(.system(.body, design: .serif))
                .foregroundStyle(Color("textPrimary"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    static func parseMarkdown(_ text: String) -> AttributedString {
        let processed = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("- ") {
                    return "\u{2022} " + String(trimmed.dropFirst(2))
                }
                if trimmed.hasPrefix("* ") {
                    return "\u{2022} " + String(trimmed.dropFirst(2))
                }
                return String(line)
            }
            .joined(separator: "\n")

        do {
            return try AttributedString(
                markdown: processed,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace
                )
            )
        } catch {
            return AttributedString(text)
        }
    }
}
