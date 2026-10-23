import Foundation

/// [01] These local rules describe an app, not what someone does inside it.
/// Unknown apps stay in Other; display names never decide a category.
struct AutomaticActivityClassification {
    static let revision = "2026-10-18.1"

    // [02] These exact app IDs were checked against Apple's public catalogue.
    // The phone does not send its installed-app list there.
    private static let rules: [String: FootprintCategory] = [
        "com.apple.Music": .audio,
        "com.apple.podcasts": .audio,
        "com.apple.Maps": .navigation,
        "com.apple.mobilemail": .email,
        "com.apple.MobileSMS": .messaging,
        "com.google.ios.youtube": .video,
        "com.spotify.client": .audio,
        "com.burbn.instagram": .social,
        "net.whatsapp.WhatsApp": .messaging,
        "com.google.Gmail": .email,
        "com.google.Maps": .navigation,
        "com.openai.chat": .ai,
        "com.roblox.robloxmobile": .gaming
    ]

    // [03] Use only a known app ID to choose a category. An unknown app stays in Other,
    // so a friendly display name cannot quietly change its estimate.
    static func category(bundleIdentifier: String?) -> FootprintCategory {
        guard let bundleIdentifier else { return .other }
        return rules[bundleIdentifier] ?? .other
    }

    /// [04] Keep the reviewed assumptions, but leave usage time for Apple to supply.
    /// New categories use the shared model's starting assumptions.
    static func assumptions(preserving existing: FootprintInputs?) -> FootprintInputs {
        var result = existing ?? .empty
        result.usages = FootprintCategory.allCases.map { category in
            var usage = existing?.usages.first { $0.category == category }
                ?? SharedFootprintCalculator.exampleUsage(for: category)
            usage.minutes = 0
            return usage
        }
        return result
    }
}
