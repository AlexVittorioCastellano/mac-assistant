import Foundation

public enum MacHelpChat {
    public static var instructions: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return Prompts.base + "\n\n" + L.t("chat.instructions", version.majorVersion)
    }

    public static func guides(for question: String) -> [String] {
        MacHowTo.matching(question)
    }

    public static func prompt(for question: String) -> String {
        prompt(for: question, guides: guides(for: question))
    }

    public static func prompt(for question: String, guides: [String]) -> String {
        guard !guides.isEmpty else {
            return question + "\n\n" + L.t("chat.noGuide")
        }
        return question + "\n\n" + L.t("chat.guideHeader") + "\n"
            + guides.map { "- \($0)" }.joined(separator: "\n")
    }
}

extension MacHelpChat {
    public static func answerNeedsGuide(_ answer: String, guides: [String]) -> Bool {
        guard !guides.isEmpty else { return false }

        let modifiers: Set<Character> = ["⌘", "⇧", "⌥", "⌃"]

        let allowed = Set(guides.flatMap(shortcuts)
            + shortcuts(in: instructions).filter { !$0.allSatisfy(modifiers.contains) })
        return shortcuts(in: answer).contains { !allowed.contains($0) }
    }

    static func shortcuts(in text: String) -> [String] {
        let modifiers: Set<Character> = ["⌘", "⇧", "⌥", "⌃"]
        let stops: Set<Character> = [" ", "\n", ".", ",", ";", ":", ")", "»", "*", "("]
        var result: [String] = []
        var i = text.startIndex
        while i < text.endIndex {
            guard modifiers.contains(text[i]) else { i = text.index(after: i); continue }
            var j = i
            while j < text.endIndex, modifiers.contains(text[j]) { j = text.index(after: j) }

            let modifierCount = text.distance(from: i, to: j)
            if j < text.endIndex, !text[j].isWhitespace,
               !(modifierCount == 1 && stops.contains(text[j])) {
                j = text.index(after: j)
            }
            while j < text.endIndex, !stops.contains(text[j]) { j = text.index(after: j) }

            let spaceKey = " " + L.t("chat.spaceKey")
            if text[i..<j].allSatisfy(modifiers.contains), text[j...].hasPrefix(spaceKey) {
                j = text.index(j, offsetBy: spaceKey.count)
            }
            result.append(String(text[i..<j]))
            i = j
        }
        return result
    }
}

public enum MacHowTo {
    static var entries: [LanguagePack.Guide] { L.current.guides }

    static func matching(_ question: String) -> [String] {
        let text = IntentRouter.normalize(question)
        func matches(_ keyword: String) -> Bool {
            keyword.split(separator: "+").allSatisfy { IntentRouter.hasStem(text, String($0)) }
        }
        return Array(entries.filter { $0.keywords.contains(where: matches) }.prefix(2).map(\.text))
    }
}
