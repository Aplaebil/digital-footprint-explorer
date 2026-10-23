import SwiftUI
import WidgetKit

/// [01] Widget placement belongs to iOS; this view shows its shortest supported route.
struct WidgetHelpScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasConfiguredWidget: Bool?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("A little piece of your garden, right on your Home Screen.")
                        .font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text(hasConfiguredWidget == true
                         ? "A garden widget is configured. You can add another size whenever you like."
                         : "Keep a small reminder of your day close, without opening the app.")
                        .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("widget-help.status")
                }
                Section("A quick way to add it") {
                    // [02] Show the shortest supported Home Screen route for this iOS version, without promising one-tap placement.
                    if #available(iOS 18.0, *) {
                        Text("Touch and hold the Digital Footprint app icon on your Home Screen.")
                            .accessibilityIdentifier("widget-help.quickStart")
                        Text("Tap the small or medium widget size in the menu.")
                        Text("This turns the app icon into a widget. Tap the widget to open your garden.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Text("Touch and hold an empty area of your Home Screen.")
                            .accessibilityIdentifier("widget-help.quickStart")
                        Text("Tap +, find Digital Footprint and choose Your garden. Pick a size, then tap Add Widget.")
                    }
                }
                Section("Keep the app icon too") {
                    Text("Touch and hold an empty area of the Home Screen. Tap Edit, then Add Widget. On earlier iOS versions, tap +.")
                    Text("Find Digital Footprint, choose Your garden and a size, then tap Add Widget.")
                    Text("Use this route too if widget sizes do not appear when you hold the app icon.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("What it shows") {
                    Text("The widget shows your latest saved garden, estimate, date and input source. Tap it to open Today.")
                    Text("Only this small summary is shared with the widget. Your detailed inputs and garden preferences stay in the app.")
                    Text("It updates after the app imports a completed day. iOS decides when the change appears, so it may take a little time.")
                    if !FootprintWidgetPublisher.isAvailable {
                        Text("Widget updates are not available in this build. Your garden and entries still work in the app.")
                    }
                }
                Section {
                    Link("Open Apple's widget guide", destination: URL(string: "https://support.apple.com/en-ie/guide/iphone/iphb8f1bf206/27/ios/27")!)
                        .frame(minHeight: 44).accessibilityIdentifier("widget-help.appleGuide")
                } footer: {
                    Text("You choose where the widget belongs. iOS asks you to add it from the Home Screen; the app cannot place it for you.")
                }
            }
            .scrollContentBackground(.hidden).background(FootprintAppearance.page)
            .accessibilityIdentifier("widget-help.content")
            .navigationTitle("Your garden widget").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { checkConfiguration() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { checkConfiguration() }
            }
        }
    }

    private func checkConfiguration() {
        // [03] Separate layout tests must not inspect the person's installed widgets.
        if AutomaticOnboardingView.isControlledPreview { return }
        WidgetCenter.shared.getCurrentConfigurations { result in
            let found = try? result.get().contains { $0.kind == GardenWidgetSnapshot.widgetKind }
            Task { @MainActor in hasConfiguredWidget = found }
        }
    }
}
