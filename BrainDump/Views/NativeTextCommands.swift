import SwiftUI

struct NativeTextCommands: Commands {
    let state: NativeCommandState

    var body: some Commands {
        CommandGroup(replacing: .textEditing) {
            Menu("Spelling and Grammar") {
                action("Show Spelling and Grammar", .spellingPanel).keyboardShortcut(";", modifiers: [.command, .shift])
                action("Check Document Now", .checkSpelling).keyboardShortcut(";")
                Divider()
                toggle("Check Spelling While Typing", .continuousSpelling)
                toggle("Check Grammar With Spelling", .grammar)
                toggle("Correct Spelling Automatically", .correction)
            }
            Menu("Substitutions") {
                action("Show Substitutions", .substitutionsPanel)
                Divider()
                toggle("Smart Quotes", .quotes)
                toggle("Smart Dashes", .dashes)
                toggle("Text Replacement", .replacement)
                toggle("Smart Links", .links)
            }
            Menu("Transformations") {
                action("Make Upper Case", .uppercase)
                action("Make Lower Case", .lowercase)
                action("Capitalize", .capitalize)
            }
            Menu("Speech") {
                action("Start Speaking", .startSpeaking)
                action("Stop Speaking", .stopSpeaking)
            }
        }
    }

    private func action(_ title: LocalizedStringKey, _ action: NativeCommandState.Action) -> some View {
        Button(title) { state.perform(action) }.disabled(!state.status(action).isEnabled)
    }

    private func toggle(_ title: LocalizedStringKey, _ action: NativeCommandState.Action) -> some View {
        Toggle(title, isOn: Binding(get: { state.status(action).isOn }, set: { _ in state.perform(action) }))
            .disabled(!state.status(action).isEnabled)
    }
}
