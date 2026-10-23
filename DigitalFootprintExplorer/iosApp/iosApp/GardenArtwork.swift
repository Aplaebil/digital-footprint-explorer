import SwiftUI

/// [01] The same five transparent garden pictures used by the Android app.
struct GardenArtwork: View {
    let state: FootprintGarden
    var maximumWidth: CGFloat = 320

    // [02] Choose the picture from the saved garden state, so the app and widget tell the same story.
    static func imageName(for state: FootprintGarden) -> String {
        switch state {
        case .flourishing: "GardenFlourishing"
        case .growing: "GardenGrowing"
        case .stable: "GardenStable"
        case .wilting: "GardenWilting"
        case .withered: "GardenWithered"
        }
    }

    var body: some View {
        // [03] Fit the complete original image; keep its colors and transparency.
        Image(Self.imageName(for: state))
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: maximumWidth)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Garden: \(state.title)")
            .accessibilityIdentifier("garden.artwork")
    }
}
