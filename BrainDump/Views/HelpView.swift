import SwiftUI

struct HelpView: View {
    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: "BrainDumpHelp", withExtension: "html", subdirectory: "Help")
                ?? Bundle.main.url(forResource: "BrainDumpHelp", withExtension: "html") {
                LocalHelpWebView(url: url)
            } else {
                InlineMessage(message: String(localized: "The bundled BrainDump Help could not be opened."))
                    .padding()
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .background(AuxiliaryWindowAttachment())
    }
}
