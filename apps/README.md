# App projects

Both apps use the calculation model in [`../shared/`](../shared/). Their interfaces and platform integrations stay in separate folders.

| Folder | Contents | Open with |
| --- | --- | --- |
| [`android/`](android/) | Existing Android application, background worker and widget | Android Studio, from the repository root |
| [`ios/`](ios/) | Native SwiftUI app, WidgetKit extension and local iOS tools | Xcode: `ios/iosApp.xcodeproj` |

The Gradle wrapper and dependency versions are at the repository root. Run Android commands from there:

```sh
./gradlew :digitalFootprintExplorer-android:assembleDebug
```

Use `gradlew.bat` on Windows. Android builds need the configured Android SDK.

For the iPhone app, select the **iosApp-ScreenTime** scheme in Xcode. The build creates the shared Kotlin framework before compiling the app. See the [iOS guide](ios/README.md) for JDK setup, simulators, device signing and tests.

The [root README](../README.md) explains the folder proposal, current features and release limits.
