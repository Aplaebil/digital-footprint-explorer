import Foundation

/// [01] A local policy is always available; public links come from release configuration.
enum ReleaseLinks {
    static var privacyPolicy: URL? { secureURL(for: "DFEPrivacyPolicyURL") }
    static var support: URL? { secureURL(for: "DFESupportURL") }
    // [02] Show the version that was actually bundled, so support can identify the installed build.
    static var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }
    // [03] Hide a missing or unsafe release link instead of opening an incomplete web address.
    private static func secureURL(for key: String) -> URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              let url = URL(string: value), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}
