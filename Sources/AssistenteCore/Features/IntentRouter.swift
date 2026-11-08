import Foundation

public enum Intent: Sendable, Equatable {
    case slowMac
    case diskSpace

    case healthCheck

    case securityScan

    case cleanup

    case process(String?)

    case chat
}

public enum IntentRouter {
    static var router: LanguagePack.Router { L.current.router }
    static var slowKeywords: [String] { router.slow }
    static var diskKeywords: [String] { router.disk }
    static var healthKeywords: [String] { router.health }
    static var cleanupKeywords: [String] { router.cleanup }
    static var securityKeywords: [String] { router.security }
    static var strongSlowKeywords: [String] { router.strongSlow }
    static var processTriggers: [String] { router.processTriggers }
    static var fillerWords: Set<String> { Set(router.fillerWords) }

    public static func route(_ question: String, runningNames: [String] = []) -> Intent {
        let text = normalize(question)

        if let quoted = quotedName(in: question) { return .process(quoted) }

        let asksAboutProcess = processTriggers.contains { hasStem(text, $0) }
        if asksAboutProcess {
            if let name = runningName(in: text, among: runningNames) {
                if let candidate = candidateName(in: question),
                   normalize(candidate).count > name.count,
                   containsWord(normalize(candidate), normalize(name)) {
                    return .process(candidate)
                }
                return .process(name)
            }

            if let topic = topic(of: text) { return topic }

            return .process(candidateName(in: question))
        }
        return topic(of: text) ?? .chat
    }

    public static func isFollowUp(_ question: String) -> Bool {
        let t = normalize(question).trimmingCharacters(in: .whitespaces)
        return router.followUp.contains { t.hasPrefix($0) }
    }

    public static func isHowTo(_ question: String) -> Bool {
        let t = normalize(question)
        return router.howTo.contains { hasStem(t, $0) }
    }

    static func topic(of normalized: String) -> Intent? {
        if cleanupKeywords.contains(where: { hasStem(normalized, $0) }) { return .cleanup }
        if securityKeywords.contains(where: { hasStem(normalized, $0) }) { return .securityScan }
        if healthKeywords.contains(where: { hasStem(normalized, $0) }) { return .healthCheck }
        let strongSlow = strongSlowKeywords.contains { hasStem(normalized, $0) }
        let disk = diskKeywords.contains { hasStem(normalized, $0) }
        if disk && !strongSlow { return .diskSpace }
        return isAboutSlowness(normalized) ? .slowMac : nil
    }

    static func isAboutSlowness(_ normalized: String) -> Bool {
        slowKeywords.contains { hasStem(normalized, $0) }
    }

    public static func hasStem(_ text: String, _ stem: String) -> Bool {
        var searchRange = text.startIndex..<text.endIndex
        while let r = text.range(of: stem, range: searchRange) {
            if r.lowerBound == text.startIndex { return true }
            let before = text[text.index(before: r.lowerBound)]
            if !(before.isLetter || before.isNumber || before == "_") { return true }
            searchRange = r.upperBound..<text.endIndex
        }
        return false
    }

    static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: "’", with: "'")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: L.locale)
    }

    static func quotedName(in s: String) -> String? {
        for (open, close) in [("«", "»"), ("“", "”"), ("\"", "\"")] {
            guard let a = s.range(of: open),
                  let b = s.range(of: close, range: a.upperBound..<s.endIndex) else { continue }
            let name = s[a.upperBound..<b.lowerBound].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return name }
        }
        return nil
    }

    static func runningName(in normalizedText: String, among names: [String]) -> String? {
        names
            .filter { $0.count >= 3 }
            .sorted { $0.count > $1.count }
            .first { containsWord(normalizedText, normalize($0)) }
    }

    static func containsWord(_ text: String, _ word: String) -> Bool {
        var searchRange = text.startIndex..<text.endIndex
        while let r = text.range(of: word, range: searchRange) {
            let before = r.lowerBound == text.startIndex ? nil : text[text.index(before: r.lowerBound)]
            let after = r.upperBound == text.endIndex ? nil : text[r.upperBound]
            let isBoundary: (Character?) -> Bool = { c in
                guard let c else { return true }
                return !(c.isLetter || c.isNumber || c == "_")
            }
            if isBoundary(before) && isBoundary(after) { return true }
            searchRange = r.upperBound..<text.endIndex
        }
        return false
    }

    static func candidateName(in question: String) -> String? {
        let separators = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "?!.,;:'’"))
        let words = question.components(separatedBy: separators).filter { !$0.isEmpty }
        let kept = words.filter { !fillerWords.contains(normalize($0)) }
        return kept.isEmpty ? nil : kept.joined(separator: " ")
    }
}
