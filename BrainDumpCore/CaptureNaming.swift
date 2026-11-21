import Foundation

/// Technical names never inherit display locale, calendar, numerals, or time zone.
nonisolated struct CaptureNaming: Sendable {
    let firstSavedAt: Date

    var timestampStem: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: firstSavedAt)
    }

    var monthFolder: String { String(timestampStem.prefix(7)) }

    func filename(suffix: UInt = 0) -> String {
        guard suffix > 0 else { return timestampStem + ".md" }
        let digits = String(suffix)
        let padded = String(repeating: "0", count: max(0, 2 - digits.count)) + digits
        return timestampStem + "_" + padded + ".md"
    }
}
