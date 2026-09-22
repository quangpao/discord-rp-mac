import SwiftUI

/// Applies a hover tooltip only when there is something to say — `.help("")` would pop an empty
/// bubble.
struct OptionalHelp: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if let text, !text.isEmpty {
            content.help(text)
        } else {
            content
        }
    }
}

extension View {
    /// Tooltip from an optional string; a no-op when the string is nil or empty.
    ///
    /// The editor keeps its explanations here rather than in a caption line under every control: the
    /// placeholder carries the essence, the tooltip carries the detail, and a line of text is spent
    /// only when the state needs attention (a warning, an error, a status).
    func optionalHelp(_ text: String?) -> some View {
        modifier(OptionalHelp(text: text))
    }
}
