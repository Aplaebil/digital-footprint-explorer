# Digital Footprint Explorer for iOS

The iPhone app uses the existing shared emission model. It turns the available Screen Time activity into a daily estimate, a garden and a local history. The small and medium Home Screen widgets show the latest saved garden.

| Today | History | Settings |
| --- | --- | --- |
| ![Today with a green garden](docs/images/ios-today.png) | ![Saved daily estimates](docs/images/ios-history.png) | ![Connection and privacy settings](docs/images/ios-settings.png) |

These previews use isolated example history. They show the interface, not measured activity or verified emissions.

## Build and run

Use a Mac with Xcode, the iOS 26.4 or later SDK, JDK 17 and an installed iPhone simulator. The app and widget require iOS 26.4 or later. The Gradle wrapper in `DigitalFootprintExplorer/` builds the neighbouring `shared/` module; there is no separate copy of the calculation model in Swift.

1. Open `DigitalFootprintExplorer/iosApp/iosApp.xcodeproj` from the repository root.
2. Select `iosApp-ScreenTime`, then choose an iPhone simulator and run. Xcode builds the shared framework before the app.
3. For a physical iPhone, copy `Configuration/Local.xcconfig.example` to `Configuration/Local.xcconfig`. Use your approved Apple team and matching app/widget identifiers, App Group and provisioning profiles. Keep this local signing file out of Git.
4. On a supported device, choose **Enable automatic estimates** and complete Apple's authorization. No daily form or app-by-app selection is required. A completed day stays pending until Apple supplies usable activity.

The ordinary `iosApp` scheme is also available for builds without the expanded Screen Time route. Changing a scheme or entitlement file does not grant Apple's permission.

## Automatic estimates and privacy

Screen Time supplies the app durations that Apple makes available. Traffic, brightness, GPS, Bluetooth and carbon emissions remain model assumptions or estimates; they are not measurements collected from other apps. The interface explains those limits.

The app keeps its history on the iPhone. Its App Group holds only the latest garden summary needed by the widget. There is no DFE account, activity-upload service or remote push server. Optional morning notices are local notifications. iOS chooses background execution and widget refresh opportunities, so the app cannot promise an update at exactly 08:00.

Family Controls and App and Website Usage need the correct capabilities, profiles and user authorization. Apple's published expanded-access customer conditions include an EU-located device and an EU Apple Account region. Development testing elsewhere does not prove customer availability there. Check [Apple's entitlement guide](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement) and [expanded access conditions](https://developer.apple.com/documentation/familycontrols/authorizationstatus/approvedwithdataaccess) before choosing release countries.

The offline policy is in the app. Approved public privacy and support URLs still need to be set in the release configuration and App Store Connect before distribution.

## Run the checks

From the repository root:

```sh
python3 -m unittest discover -s DigitalFootprintExplorer/iosApp/tests -v
python3 DigitalFootprintExplorer/iosApp/scripts/generate_privacy_policy.py --check
bash DigitalFootprintExplorer/iosApp/scripts/ios-check.sh
```

The last command runs the new shared iOS bridge tests and the controlled native unit tests. It does not claim a full shared-suite pass: the existing emission-calculator fixture correction is kept in a separate pull request for its own review. Set `DFE_SIMULATOR_ID` to choose a particular installed simulator. It writes an `.xcresult` bundle outside the repository by default and prints its path. These tests use isolated stores and do not request personal Screen Time access.

To run the interface tests, replace the destination below with an installed iPhone simulator:

```sh
xcodebuild -project DigitalFootprintExplorer/iosApp/iosApp.xcodeproj \
  -scheme iosApp-ScreenTime -configuration ScreenTimeDebug \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:iosAppUITests test
```

Live Screen Time import, a natural new-day background update, visible widget refresh and notice delivery need separate physical-device acceptance. Simulator tests and compilation do not establish those results or App Store readiness.

## Local tools

Edit the policy in `Configuration/PrivacyPolicyContent.json`, then run `scripts/generate_privacy_policy.py`. The default updates only `iosApp/PrivacyPolicyContent.swift`. `--include-web` also exports matching HTML and Markdown into this iOS folder's `docs/` directory for a separate website review. It does not publish them or change the repository's existing website.

`scripts/check-ios-release.py` inspects a built bundle or archive without uploading it or changing signing resources. Pass `--require-store` when a distribution signature, approved public URLs and matching Store profiles are required. Its `--project-root` input is the repository root.

```text
DigitalFootprintExplorer/iosApp/
├── Configuration/          # Capabilities, policy source and local signing example
├── iosApp.xcodeproj/       # Xcode project and shared schemes
├── iosApp/                 # SwiftUI app, local storage and automatic refresh
├── GardenWidget/           # Small and medium WidgetKit layouts
├── WidgetShared/           # Garden states and the saved widget summary
├── iosAppTests/            # Controlled model, storage and refresh tests
├── iosAppUITests/          # Navigation, layout and accessibility tests
├── scripts/                # Local build, policy and release checks
├── tests/                  # Python tests for those checks
└── docs/images/            # Interface previews using example history
```

The app remains under review. A release still needs a validated distribution build, approved privacy/support pages, confirmed customer regions and successful device acceptance.
