import Foundation
import Security

public enum ProcessKind: Sendable, Equatable {
    case macOS

    case app(name: String)

    case appComponent(appName: String)

    case background

    case unknown

    public static func classify(path: String?, user: String) -> ProcessKind {
        let systemUser = user == "root" || user.hasPrefix("_")
        guard let path, path.hasPrefix("/") else {
            return systemUser ? .macOS : .unknown
        }

        if path.contains("/Applications/"), let app = appBundle(in: path) {
            return app.isMainExecutable ? .app(name: app.name) : .appComponent(appName: app.name)
        }

        let systemPrefixes = ["/System/", "/usr/", "/sbin/", "/bin/", "/Library/Apple/"]
        if systemPrefixes.contains(where: path.hasPrefix) && !path.hasPrefix("/usr/local/") {
            return .macOS
        }

        if path.contains("/com.apple.") || path.contains("/.com.apple.") {
            return .macOS
        }

        return .background
    }

    public static func classifyVerifyingSignature(path: String?, user: String) -> ProcessKind {
        let kind = classify(path: path, user: user)
        if kind == .background, let path, isSignedByAppleAsSystem(path) { return .macOS }
        return kind
    }

    static func isSignedByAppleAsSystem(_ path: String) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess,
              let code else { return false }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString("anchor apple" as CFString, [], &requirement) == errSecSuccess else { return false }
        return SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    static func appBundle(in path: String) -> (name: String, isMainExecutable: Bool)? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard let i = parts.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        let bundlePath = "/" + parts[...i].joined(separator: "/")
        let rest = parts[(i + 1)...]
        let isMain = rest.count == 3 && rest.first == "Contents" && rest.dropFirst().first == "MacOS"
        return (displayName(ofBundleAt: bundlePath), isMain)
    }

    public static func outermostAppBundlePath(in path: String?) -> String? {
        guard let path, path.hasPrefix("/") else { return nil }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard let i = parts.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return "/" + parts[...i].joined(separator: "/")
    }

    static func displayName(ofBundleAt path: String) -> String {
        let info = Bundle(path: path)?.infoDictionary
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let name = (info?[key] as? String).map(cleaned), !name.isEmpty { return name }
        }
        return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    static func cleaned(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.filter { $0.properties.generalCategory != .format }))
            .trimmingCharacters(in: .whitespaces)
    }
}
