import SwiftUI
import UIKit

// [01] Daily updates are optional. Let the person choose them without making notifications
// a condition for seeing their garden or importing Screen Time.
struct GardenNotificationSettingsSection: View {
    @ObservedObject var notifications: GardenNotificationService
    var afterEnable: () async -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("A morning moment").font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("settings.notificationHeading")
            VStack(spacing: 0) {
                Toggle(isOn: Binding(get: { notifications.enabled }, set: { requested in
                    Task {
                        await notifications.setEnabled(requested)
                        if notifications.enabled { await afterEnable() }
                    }
                })) {
                    SettingsActionLabel("Daily garden update", symbol: "bell.badge")
                }
                .tint(FootprintAppearance.accent)
                .disabled(notifications.isUpdating)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityIdentifier("settings.dailyGardenNotification")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("settings.dailyGardenNotificationRow")
            Text("A short update around 8:00 in your local time, after yesterday's estimate is ready. Some days may arrive later; days without usable activity stay quiet.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("settings.notificationTiming")
            // [02] After Apple refuses access, send the person to the system control rather than repeatedly asking.
            if notifications.authorizationDenied {
                Button {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                } label: {
                    SettingsActionLabel("Open notification settings", symbol: "bell", showsChevron: true)
                }
                .accessibilityIdentifier("settings.notificationPermissions")
            }
            if let message = notifications.errorMessage {
                Text(message).font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.section.notifications")
        .task { await notifications.refreshPreference() }
    }
}
