import SwiftUI

// [01] Keep track of what started an update so a pull and an automatic retry use the same path.
enum AppRefreshTrigger: String, Sendable {
    case applicationRefresh = "application_refresh"
    case pullToRefresh = "pull_to_refresh"
}

private struct AutomaticRefreshModifier: ViewModifier {
    #if DEBUG
    @State private var completedPulls = 0
    private var recordsTestPulls: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-ui-testing") && args.contains("-ui-refresh-test")
    }
    #endif

    @ViewBuilder
    // [02] Every tab uses this refresh action, even when its content is short.
    // The spinner stays active while the shared update finishes.
    func body(content: Content) -> some View {
        let refreshed = content.scrollBounceBehavior(.always, axes: .vertical).refreshable {
            await AppServices.shared.refresh(trigger: .pullToRefresh)
            #if DEBUG
            if recordsTestPulls { completedPulls += 1 }
            #endif
        }
        #if DEBUG
        if recordsTestPulls {
            // [03] Tests observe completed gestures, not a claim that Apple supplied data.
            refreshed.accessibilityValue("Completed refreshes: \(completedPulls)")
        } else {
            refreshed
        }
        #else
        refreshed
        #endif
    }
}

extension View {
    func automaticRefresh() -> some View {
        modifier(AutomaticRefreshModifier())
    }
}
