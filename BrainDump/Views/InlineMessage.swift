import SwiftUI

struct InlineMessage: View {
    let message: String
    var body: some View {
        Text(message)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .accessibilityAddTraits(.isStaticText)
    }
}
