import Foundation

nonisolated struct CaptureTitleFormatter: Sendable {
    func title(projectName: String, firstSavedAt: Date?, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        guard let firstSavedAt else { return "\(projectName) - BrainDump - \(String(localized: "New Capture", locale: locale))" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "\(projectName) - BrainDump - \(formatter.string(from: firstSavedAt))"
    }
}
