# Digital Footprint Explorer for iOS

The iPhone app uses the existing shared emission model. It turns the available Screen Time activity into a daily estimate, a garden and a local history. The small and medium Home Screen widgets show the latest saved garden.

| Today | History | Settings |
| --- | --- | --- |
| ![Today with a green garden](docs/images/ios-today.png) | ![Saved daily estimates](docs/images/ios-history.png) | ![Connection and privacy settings](docs/images/ios-settings.png) |

These previews use isolated example history. They show the interface, not measured activity or verified emissions.

## Build and run

Use a Mac with Xcode 27.1, JDK 17 and an installed iPhone simulator. The build needs the iOS 27 SDK for the newer background-task API; the app and widget can run on iOS 26.4 or later. The Gradle wrapper in `DigitalFootprintExplorer/` builds the neighbouring `shared/` module; there is no separate copy of the calculation model in Swift.

1. Open `DigitalFootprintExplorer/iosApp/iosApp.xcodeproj` from the repository root.
2. Select `iosApp-ScreenTime`, then choose an iPhone simulator and run. Xcode builds the shared framework before the app.
3. For a physical iPhone, copy `Configuration/Local.xcconfig.example` to `Configuration/Local.xcconfig`. Use your approved Apple team and matching app/widget identifiers, App Group and provisioning profiles. Keep this local signing file out of Git.
4. On a supported device, choose **Enable automatic estimates** and complete Apple's authorization. No daily form or app-by-app selection is required. A completed day stays pending until Apple supplies usable activity.

The ordinary `iosApp` scheme is also available for builds without the expanded Screen Time route. Changing a scheme or entitlement file does not grant Apple's permission.

## Automatic estimates and privacy

Screen Time supplies the app durations that Apple makes available. Traffic, brightness, GPS, Bluetooth and carbon emissions remain model assumptions or estimates; they are not measurements collected from other apps. The interface explains those limits.

The app keeps its history on the iPhone. Its App Group holds only the latest garden summary needed by the widget. There is no DFE account, activity-upload service or remote push server. Optional morning notices are local notifications. iOS chooses background execution and widget refresh opportunities, so the app cannot promise an update at exactly 08:00.

Family Controls and App and Website Usage need the correct capabilities, profiles and user authorization. Apple's published expanded-access customer conditions include an EU-located device and an EU Apple Account region. Development testing elsewhere does not prove customer availability there. Check [Apple's entitlement guide](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement) and [expanded access conditions](https://developer.apple.com/documentation/familycontrols/authorizationstatus/approvedwithdataaccess) before choosing release countries.

The offline policy is in the app. The approved privacy and support addresses are set in the release configuration. Their pages are included in this pull request and will deploy through GitHub Pages after it is merged. Both addresses must return the correct public page before a release is uploaded; their App Store Connect fields also need to match.

## Run the checks

From the repository root:

```sh
python3 -m unittest discover -s DigitalFootprintExplorer/iosApp/tests -v
python3 DigitalFootprintExplorer/iosApp/scripts/generate_privacy_policy.py --check
python3 DigitalFootprintExplorer/iosApp/scripts/generate_privacy_policy.py --check --include-web
bash DigitalFootprintExplorer/iosApp/scripts/ios-check.sh
```

The last command runs all 24 shared calculation tests, including the iOS bridge and the corrected time-unit fixtures, followed by the controlled native unit tests. Set `DFE_SIMULATOR_ID` to choose a particular installed simulator. It writes an `.xcresult` bundle outside the repository by default and prints its path. These tests use isolated stores and do not request personal Screen Time access.

GitHub Actions runs these checks for pull requests to `main` and saves the logs, shared reports and `.xcresult` as an artifact for 14 days. The workflow uses GitHub's arm64 `xcode-27` preview image with Xcode 27.1. It does not use signing credentials or run the live Screen Time phone tests. A maintainer may need to approve the first run from a fork; adding the workflow is not evidence that its hosted run has passed.

To run the interface tests, replace the destination below with an installed iPhone simulator:

```sh
xcodebuild -project DigitalFootprintExplorer/iosApp/iosApp.xcodeproj \
  -scheme iosApp -configuration ScreenTimeDebug \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:iosAppUITests test
```

Live Screen Time import, a natural new-day background update, visible widget refresh and notice delivery need separate physical-device acceptance. Simulator tests and compilation do not establish those results or App Store readiness.

## Local tools

Edit the policy in `Configuration/PrivacyPolicyContent.json`, then run `scripts/generate_privacy_policy.py`. The default updates only `iosApp/PrivacyPolicyContent.swift` and leaves the website alone. Add `--include-web` to update the same policy's HTML, Markdown and JSON copies in the repository's root `docs/` folder. No extra public copies are created inside this iOS folder. Use `--check --include-web` to report differences without changing any file.

The generated public files are `docs/privacy-policy.html`, `docs/privacy-policy.md` and `docs/privacy-policy-content.json` at the repository root. Generating them does not deploy the website. GitHub Pages publishes the repository's approved website source after the pull request is merged.

`scripts/check-ios-release.py` inspects a built bundle or archive without uploading it or changing signing resources. Pass `--require-store` when a distribution signature, approved public URLs and matching Store profiles are required. Its `--project-root` input is the repository root.

The export options and Store checker target the ZHAW release identity. Development signing still comes from your ignored `Local.xcconfig`; cloning the project does not select the ZHAW team.

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

The app remains under review. A release still needs a validated distribution build, successfully deployed privacy/support pages, confirmed customer regions and successful device acceptance.

## Public pages and contact

DFE Team maintains the app and handles privacy and support questions at [digital-footprint-explorer.init@zhaw.ch](mailto:digital-footprint-explorer.init@zhaw.ch). The policy and support pages are included under the repository’s `docs/` folder in the same final pull request. Their HTTPS addresses are set in `Configuration/Config.xcconfig`; verify that GitHub Pages has deployed both pages before uploading a release. A pending deployment is a release gate. The offline policy remains available without visiting the website.
