import SwiftUI

/// [01] The local copy stays readable even when the phone has no internet connection.
struct PrivacyPolicyView: View {
    var publicURL: URL? = nil

    // [02] Offer an online copy only for a complete secure web address; the local policy is still available.
    private var securePublicURL: URL? {
        guard let publicURL, publicURL.scheme?.lowercased() == "https",
              let host = publicURL.host, !host.isEmpty else { return nil }
        return publicURL
    }

    var body: some View {
        Form {
            Section {
                Text(PrivacyPolicyContent.appName).font(.headline)
                Text(PrivacyPolicyContent.updatedText)
                    .font(.subheadline).foregroundStyle(.secondary)
                ForEach(PrivacyPolicyContent.introduction, id: \.self) { paragraph in
                    Text(paragraph).fixedSize(horizontal: false, vertical: true)
                }
            }
            Section {
                Link(destination: PrivacyPolicyContent.contactURL) {
                    Label("Email the DFE team", systemImage: "envelope")
                        .frame(minHeight: 44)
                        .fixedSize(horizontal: false, vertical: true)
                }.accessibilityIdentifier("privacy.contact")
                if let securePublicURL {
                    Link(destination: securePublicURL) {
                        Label("Open online policy", systemImage: "safari")
                            .frame(minHeight: 44)
                            .fixedSize(horizontal: false, vertical: true)
                    }.accessibilityIdentifier("privacy.online")
                }
            }
            ForEach(PrivacyPolicyContent.sections) { section in
                Section {
                    ForEach(section.paragraphs, id: \.self) { paragraph in
                        Text(paragraph).fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text(section.title)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(FootprintAppearance.page)
        .navigationTitle(PrivacyPolicyContent.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("privacy.policy")
    }
}
