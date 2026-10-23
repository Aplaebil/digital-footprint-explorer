# Application workspace

This folder contains the Android app, the shared calculation model and the native iOS project. Start with the [project guide](../README.md) for setup, verification and the current release limits.

- [Android application sources](digitalFootprintExplorer-android/src) contain the existing Android screens, collectors, worker and widget.
- [Shared sources](shared/src) contain the calculation, database definitions, migrations and model tests used by both platforms.
- [Native iOS workspace](iosApp) contains the SwiftUI app, garden widget, shared configuration and native tests. Open `iosApp/iosApp.xcodeproj` in Xcode and use the automatic Screen Time scheme for the supported iOS path.
- [Architecture diagrams](diagrams) describe the inherited Android reference. Their labels are historical context, rather than a specification of Apple's current APIs.

Use the checked-in Gradle wrapper for shared and Android builds. Keep personal signing settings outside Git. Build output can be recreated and is excluded from the final handover.
