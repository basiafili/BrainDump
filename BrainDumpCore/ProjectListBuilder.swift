import Foundation

nonisolated enum ProjectListEntry: Equatable, Sendable {
    case project(ProjectRecord)
    case group(label: String, projects: [ProjectRecord])

    var projects: [ProjectRecord] {
        switch self {
        case .project(let project): [project]
        case .group(_, let projects): projects
        }
    }
}

/// Both compact selectors must render this same structure, not regroup it in views.
nonisolated struct ProjectListBuilder {
    let locale: Locale

    init(locale: Locale = .current) { self.locale = locale }

    func build(_ projects: [ProjectRecord]) -> [ProjectListEntry] {
        let sorted = projects.sorted(by: precedes)
        guard sorted.count > 15 else { return sorted.map(ProjectListEntry.project) }

        struct Bucket {
            let script: String
            let comparisonKey: String
            let visibleKey: String
            var projects: [ProjectRecord]
        }
        var buckets: [Bucket] = []
        var fallback: [ProjectRecord] = []
        for project in sorted {
            let key = String(project.name.prefix(1)).uppercased(with: locale)
            guard key.unicodeScalars.first.map({ CharacterSet.letters.contains($0) }) == true else {
                fallback.append(project)
                continue
            }
            let comparisonKey = key.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
            let script = scriptKey(for: key)
            if let last = buckets.last, last.script == script, last.comparisonKey == comparisonKey {
                buckets[buckets.count - 1].projects.append(project)
            } else {
                buckets.append(Bucket(script: script, comparisonKey: comparisonKey, visibleKey: key, projects: [project]))
            }
        }

        var groups: [[Bucket]] = []
        var current: [Bucket] = []
        for bucket in buckets {
            let count = current.reduce(0) { $0 + $1.projects.count }
            if let last = current.last,
               last.script != bucket.script || count + bucket.projects.count > 10 {
                groups.append(current)
                current = []
            }
            current.append(bucket)
        }
        if !current.isEmpty { groups.append(current) }

        var entries: [ProjectListEntry] = []
        for group in groups {
            let items = group.flatMap(\.projects)
            if items.count == 1 { fallback.append(contentsOf: items); continue }
            guard let first = group.first?.visibleKey, let last = group.last?.visibleKey else { continue }
            let label = first == last
                ? String(localized: "Projects starting with \(first)", locale: locale)
                : String(localized: "Projects \(first)–\(last)", locale: locale)
            entries.append(.group(label: label, projects: items))
        }
        fallback.sort(by: precedes)
        if fallback.count > 1 {
            entries.append(.group(label: String(localized: "Other projects…", locale: locale), projects: fallback))
        } else if let only = fallback.first {
            // Keep a lone orphan directly visible in its sorted position.
            let index = entries.firstIndex { entry in
                entry.projects.first.map { precedes(only, $0) } ?? false
            } ?? entries.endIndex
            entries.insert(.project(only), at: index)
        }
        return entries
    }

    private func precedes(_ lhs: ProjectRecord, _ rhs: ProjectRecord) -> Bool {
        let result = lhs.name.compare(rhs.name, options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
        if result != .orderedSame { return result == .orderedAscending }
        // Fixed tie breakers prevent equal localized names from drifting between renders.
        if lhs.name != rhs.name { return lhs.name < rhs.name }
        return lhs.folder.path < rhs.folder.path
    }

    private func scriptKey(for key: String) -> String {
        // ICU Unicode script properties classify the initial itself, rather than
        // guessing a name's language (which can combine Japanese scripts).
        let scripts = ["Latin", "Greek", "Cyrillic", "Armenian", "Hebrew", "Arabic",
                       "Syriac", "Thaana", "Nko", "Samaritan", "Mandaic", "Devanagari",
                       "Bengali", "Gurmukhi", "Gujarati", "Oriya", "Tamil", "Telugu",
                       "Kannada", "Malayalam", "Sinhala", "Thai", "Lao", "Tibetan",
                       "Myanmar", "Georgian", "Hangul", "Ethiopic", "Cherokee",
                       "Canadian_Aboriginal", "Ogham", "Runic", "Khmer", "Mongolian",
                       "Hiragana", "Katakana", "Bopomofo", "Han", "Yi", "Old_Italic",
                       "Gothic", "Deseret"]
        return scripts.first { key.range(of: "^\\p{script=\($0)}", options: .regularExpression) != nil }
            ?? "unknown:\(key)"
    }
}
