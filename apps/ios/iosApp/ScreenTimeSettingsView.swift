/*
 * Copyright (C) 2026 Zurich University of Applied Sciences, Switzerland
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import SwiftUI
import UIKit

// [01] Show one connection summary, with the detailed status available when the person wants it.
struct ScreenTimeSettingsView: View {
    @ObservedObject var store: FootprintStore
    @ObservedObject var service: ScreenTimeService
    let showSetup: () -> Void
    @State private var showDetails = false
    @State private var confirmDisconnect = false
    @State private var isDisconnecting = false
    #if DEBUG
    @State private var previewDisconnected = false
    #endif

    // [02] This separate test screen cannot grant or remove Apple's permission.
    private static var isControlledDisconnectPreview: Bool {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-ui-testing") && args.contains("-ui-automatic-preview")
            && args.contains("-ui-disconnect-preview")
        #else
        return false
        #endif
    }

    private var setupSaved: Bool { service.hasSavedAutomaticSetup(store: store) }

    // [03] Green means both the saved automatic setup and live data access are ready.
    // Permission alone does not mean the setup is complete.
    private var connected: Bool {
        #if DEBUG
        if Self.isControlledDisconnectPreview { return !previewDisconnected }
        #endif
        return setupSaved && service.state.canImport
    }

    private var canDisconnect: Bool {
        #if DEBUG
        if Self.isControlledDisconnectPreview { return !previewDisconnected }
        #endif
        #if SCREEN_TIME_ENABLED
        return service.state == .dataAccess || service.state == .reportOnly
        #else
        return false
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Screen Time")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("screen-time.heading")
                .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 20) {
                // [04] Read the connection as one short message. The shield is decoration,
                // so older iOS versions should not read its name instead of the status.
                Label {
                    Text(connected ? "Connected" : "Not connected")
                } icon: {
                    Image(systemName: statusSymbol).accessibilityHidden(true)
                }
                .font(.headline)
                .foregroundStyle(statusColor)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(connected ? "Connected" : "Not connected")
                .accessibilityIdentifier("screen-time.status")
                Text(statusExplanation)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)

            if !connected {
                Button(action: showSetup) {
                    SettingsActionLabel(service.state == .revoked ? "Reconnect Screen Time"
                                        : setupSaved ? "Review connection" : "Enable automatic estimates",
                                        symbol: "arrow.triangle.2.circlepath")
                }
                .foregroundStyle(FootprintAppearance.accent)
                .accessibilityHint(service.state == .revoked
                    ? "Resume automatic estimates. Your saved results stay available." : "")
                .accessibilityIdentifier("settings.automaticSetup")
            }

            if connected || setupSaved || service.state == .reportOnly {
                DisclosureGroup(isExpanded: $showDetails) {
                    connectionDetails.padding(.top, 12)
                } label: {
                    SettingsActionLabel("Connection details", symbol: "link")
                        .accessibilityIdentifier("screen-time.management")
                }
            }

            if let error = service.lastError { notice(error) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(DisconnectScreenTimeConfirmation(isPresented: $confirmDisconnect,
                                                  disconnect: disconnect))
    }

    // [05] Explain the scope and last import in one place, then keep Disconnect behind an explicit confirmation.
    private var connectionDetails: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(service.activityScope == .allAuthorizedApps
                 ? "All available app activity is included. Unknown apps are grouped under Other apps."
                 : "Your saved activity choices are kept. Review the connection to include all available app activity.")
                .accessibilityIdentifier("screen-time.allActivity")
            Text("Completed days update when the app opens and when iOS allows background work. Missing or incomplete days stay pending.")
            if let date = service.lastImportDate {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last import").fontWeight(.medium)
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                }
                .accessibilityElement(children: .combine)
            }
            if canDisconnect {
                Divider()
                Button(role: .destructive) {
                    confirmDisconnect = true
                } label: {
                    SettingsActionLabel("Disconnect Screen Time", symbol: "xmark.shield")
                }
                .foregroundStyle(.red)
                .disabled(isDisconnecting)
                .accessibilityHint("Asks for confirmation. Your saved daily estimates are kept.")
                .accessibilityIdentifier("screen-time-disconnect")
            }
        }
        .font(.subheadline)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func disconnect() {
        // [06] Only the alert's Disconnect action reaches Apple's permission API.
        guard !isDisconnecting else { return }
        #if DEBUG
        if Self.isControlledDisconnectPreview {
            previewDisconnected = true
            return
        }
        #endif
        isDisconnecting = true
        Task {
            await service.disconnect()
            isDisconnecting = false
        }
    }

    private var statusExplanation: String {
        #if DEBUG
        if Self.isControlledDisconnectPreview && previewDisconnected {
            return "Automatic estimates are off. Your saved days stay on this iPhone."
        }
        #endif
        if connected {
            return "Automatic daily estimates are on. Your app activity stays on this iPhone."
        }
        if service.state == .dataAccess {
            return "Screen Time access is available. Enable automatic estimates to finish the setup."
        }
        return service.state.explanation
    }

    // [07] Use words and a distinct symbol alongside colour, so the connection does not depend on colour vision.
    private var statusSymbol: String {
        #if DEBUG
        if Self.isControlledDisconnectPreview && previewDisconnected { return "xmark.shield" }
        #endif
        if connected { return "checkmark.shield" }
        switch service.state {
        case .unavailable: return "clock"
        case .notRequested, .dataAccess: return "hourglass"
        case .denied: return "hand.raised"
        case .reportOnly: return "doc.text"
        case .revoked: return "xmark.shield"
        }
    }

    private var statusColor: Color {
        if connected { return FootprintAppearance.accent }
        // [08] A deeper red stays readable on white; dark mode uses a lighter shade.
        return Color(uiColor: UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor(red: 1, green: 0.59, blue: 0.59, alpha: 1)
            }
            return traits.accessibilityContrast == .high
                ? UIColor(red: 0.57, green: 0.08, blue: 0.10, alpha: 1)
                : UIColor(red: 0.70, green: 0.12, blue: 0.15, alpha: 1)
        })
    }

    private func notice(_ error: String) -> some View {
        Label {
            Text(error).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.circle").accessibilityHidden(true)
        }
        .font(.subheadline)
        .foregroundStyle(.primary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Screen Time notice. \(error)")
    }
}
