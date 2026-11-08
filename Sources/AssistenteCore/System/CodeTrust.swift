import Foundation
import Security

public enum CodeTrust: Sendable, Equatable {
    case apple

    case appStore

    case identifiedDeveloper(String)

    case unverified

    case unsigned

    case broken

    case missing

    public var isTrusted: Bool {
        switch self {
        case .apple, .appStore, .identifiedDeveloper: true
        default: false
        }
    }

    public static func check(path: String) -> CodeTrust {
        guard FileManager.default.fileExists(atPath: path) else { return .missing }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess,
              let code else { return .unsigned }

        let flags = SecCSFlags(rawValue: kSecCSDoNotValidateResources)
        let validity = SecStaticCodeCheckValidity(code, flags, nil)
        if validity == errSecCSUnsigned { return .unsigned }
        if validity != errSecSuccess { return .broken }

        func satisfies(_ requirement: String) -> Bool {
            var req: SecRequirement?
            guard SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess else { return false }
            return SecStaticCodeCheckValidity(code, flags, req) == errSecSuccess
        }
        if satisfies("anchor apple") { return .apple }
        if satisfies("anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.9]") { return .appStore }
        if satisfies("anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13]") {
            return .identifiedDeveloper(developerName(code) ?? L.t("security.developer.registered"))
        }
        return .unverified
    }

    static func developerName(_ code: SecStaticCode) -> String? {
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any],
              let certificates = dict[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certificates.first,
              let summary = SecCertificateCopySubjectSummary(leaf) as String? else { return nil }
        return cleanDeveloperName(summary)
    }

    static func cleanDeveloperName(_ summary: String) -> String {
        var name = summary
        if let colon = name.range(of: ": ") { name = String(name[colon.upperBound...]) }
        if let paren = name.range(of: " (", options: .backwards) { name = String(name[..<paren.lowerBound]) }
        return name
    }
}
