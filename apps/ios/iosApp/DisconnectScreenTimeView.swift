import SwiftUI

// [01] The system owns the modal layout, accessibility and Liquid Glass appearance.
struct DisconnectScreenTimeConfirmation: ViewModifier {
    @Binding var isPresented: Bool
    let disconnect: () -> Void

    // [02] Give the person a clear choice before stopping future imports.
    // Cancelling keeps the connection; confirming still keeps their saved days.
    func body(content: Content) -> some View {
        content.alert("Disconnect Screen Time?", isPresented: $isPresented) {
            Button("Cancel", role: .cancel) { }
                .accessibilityIdentifier("screen-time.cancelDisconnect")
            Button("Disconnect", role: .destructive, action: disconnect)
                .accessibilityIdentifier("screen-time.confirmDisconnect")
        } message: {
            Text("Automatic estimates will pause. Your saved days will stay on this iPhone.")
        }
    }
}
