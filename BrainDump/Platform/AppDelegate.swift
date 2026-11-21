import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var runtime: CaptureAppRuntime?
    private var quitTask: Task<Void, Never>?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) { runtime?.nativeCommands.stop() }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard quitTask == nil else { return .terminateLater }
        guard let coordinator = runtime?.coordinator else { return .terminateNow }
        quitTask = Task { [weak self] in
            let result = await coordinator.prepareForAppQuit()
            let allowed: Bool
            if case .closeWindows = result { allowed = true } else { allowed = false }
            if case .failed(let issue) = result { self?.runtime?.presentBlocked(issue) }
            self?.quitTask = nil
            sender.reply(toApplicationShouldTerminate: allowed)
        }
        return .terminateLater
    }
}
