# Digital Footprint Explorer (DFE) 🌿📱

[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Android-blue)](#)
[![Institution](https://img.shields.io/badge/Developed%20at-ZHAW-red)](https://www.zhaw.ch)

> **Make the invisible environmental impacts of your digital activities visible.**

The **Digital Footprint Explorer (DFE)** is a mobile application developed at the **Zurich University of Applied Sciences (ZHAW)**. It translates unseen digital resource consumption—such as data streaming, messaging, social media usage, and AI processing—into intuitive, emotionally engaging eco-feedback.

---

## 📌 Overview

While modern digital activities feel virtual and weightless, they rely on energy-intensive infrastructure: data centers, network transmission lines, and device manufacturing. DFE addresses this disconnect by transforming abstract mobile data metrics into a tangible metaphor: **a living virtual garden**.

* **Flourishing State:** When your digital footprint remains low, your garden thrives with vibrant plants.
* **Deteriorating State:** High data-intensive consumption (such as high-definition video streaming) gradually degrades the virtual environment.

<img src="docs/images/widget.png" alt="Digital Footprint Explorer widget" width="300"/>

---

## ✨ Key Features

- **🌱 Virtual Eco-System Metaphor:** Real-time visual feedback represented via a dynamic virtual garden and desktop widget.
- **📊 Activity Classification:** Tracks and categorizes data usage from common mobile activities.
- **💡 Educational Insights:** Learn how manufacturing, data transport, and server energy contribute to overall $\text{CO}_2\text{e}$ emissions.
- **🔒 Privacy-First Architecture:** Local data processing ensures mobile network tracking stays strictly on your device.

---

## 🔒 Privacy & Data Safety
The Digital Footprint Explorer respects user privacy:
- No personal usage data, browsing history, or message content is inspected or stored outside your local device.
- Network traffic statistics are read exclusively at the aggregate system layer to compute the visual representation.

--

## Installing the App

For Android users, the app is available on the Google Play Store:

[![Get it on Google Play](https://play.google.com/intl/en_us/badges/images/generic/en_badge_web_generic.png)](https://play.google.com/store/apps/details?id=ch.zhaw.digitalfootprintexplorer&hl=en)

--

## 🤝 Contributing
Contributions are welcome! If you would like to submit bug fixes, feature requests, or scientific improvements:
1. Fork the Project.
2. Create your Feature Branch (git checkout -b feature/AmazingFeature).
3. Commit your Changes (git commit -m 'Add some AmazingFeature').
4. Push to the Branch (git push origin feature/AmazingFeature).
5. Open a Pull Request.


## Run the native iOS app

The iPhone app uses the shared Kotlin calculation model, SwiftUI and WidgetKit. The automatic Screen Time build requires iOS 26.4 or later. Use Xcode 27.1 and JDK 17 for the checked setup.

1. Clone the repository and open `DigitalFootprintExplorer/iosApp/iosApp.xcodeproj`.
2. Select the `iosApp-ScreenTime` scheme. Simulator builds need no Apple signing credentials; real Screen Time activity needs an authorized iPhone.
3. For a device build, copy `DigitalFootprintExplorer/iosApp/Configuration/Local.xcconfig.example` to `DigitalFootprintExplorer/iosApp/Configuration/Local.xcconfig`. Set your approved Apple team, Bundle ID and shared App Group. Register matching app and widget identifiers in that team and use development profiles with the required capabilities. Personal signing files stay outside Git.
4. Build and run. The app asks for Screen Time access once and imports the activity Apple makes available, without daily forms or app-by-app selection. Missing access or incomplete activity stays pending.

The host needs Family Controls and App and Website Usage; the widget needs the same App Group. Team approval, signed entitlements and the person's permission are separate requirements. Apple's customer-region rules still apply: development testing in Switzerland does not establish Swiss App Store customer access. See [Apple's entitlement guidance](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement) and [App and Website Usage](https://developer.apple.com/documentation/familycontrols).

Screen Time supplies usage duration. Carbon, traffic and the remaining model inputs are estimates. iOS schedules background work and widget updates; an exact morning delivery time is not promised. Notifications are optional and stay on the device.

### Check the code

From the repository root:

```sh
python3 -m unittest discover -s tests -v
python3 scripts/generate_privacy_policy.py --check
cd DigitalFootprintExplorer
./gradlew :shared:iosSimulatorArm64Test
xcodebuild -project iosApp/iosApp.xcodeproj -scheme iosApp-ScreenTime \
  -configuration ScreenTimeDebug -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' \
  CODE_SIGNING_ALLOWED=NO -only-testing:iosAppTests \
  -skip-testing:iosAppTests/LiveScreenTimeImportTests \
  -skip-testing:iosAppTests/LiveAllActivityImportTests test
```

Choose an installed simulator name. The two live import cases require a separate physical-device run and consent. Edit the in-app policy through `DigitalFootprintExplorer/iosApp/Configuration/PrivacyPolicyContent.json`; the generator updates the Swift copy. Website export is optional through `--include-web`.

This branch is for code review. Store signing, public privacy/support links, customer-region access and natural daily delivery still need release validation before App Store distribution.
