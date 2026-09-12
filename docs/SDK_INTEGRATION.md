# Apex Android SDK integration in Flutter

This guide mirrors the working integration in this repository. It keeps the
Flutter layer small while letting the native Apex SDK own ad loading, lifecycle,
rendering, tracking, and fullscreen activities.

## 1. Add the SDK AARs

Android libraries should be packaged as `.aar`, not `.jar`, because Apex ships
Android manifests, resources, activities, and WebView-based rendering code in
addition to JVM classes.

Place the SDK modules in variant-specific directories:

```text
android/app/libs/debug/
android/app/libs/release/
```

This demo bundles `sdk-core`, `sdk-banner`, `sdk-interstitial`, `sdk-native`,
`sdk-conversational`, `sdk-video`, `sdk-inappbidding`, `sdk-appopen`, and
`sdk-wallet`.

Wire them into `android/app/build.gradle.kts`:

```kotlin
dependencies {
    debugImplementation(fileTree("libs/debug") { include("*.aar") })
    releaseImplementation(fileTree("libs/release") { include("*.aar") })
    add("profileImplementation", fileTree("libs/release") { include("*.aar") })

    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.media3:media3-exoplayer:1.4.0")
    implementation("androidx.media3:media3-ui:1.4.0")
    implementation("com.google.android.gms:play-services-pay:16.5.0")
}
```

The extra dependencies satisfy APIs used by the SDK's fullscreen, VAST video,
and Wallet integrations.

## 2. Configure Android

Add network permissions and register your `Application` class:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />

<application
    android:name=".ApexDemoApplication"
    android:hardwareAccelerated="true">
    <!-- Flutter activity configuration -->
</application>
```

This demo enables cleartext traffic because its debug SDK talks to the local
development server. Production apps should use HTTPS and a restrictive Android
network security policy.

## 3. Initialize Apex once

Initialize the SDK in `Application.onCreate()` before any ad object is built:

```kotlin
class ApexDemoApplication : Application() {
    override fun onCreate() {
        super.onCreate()

        val config = ApexAdsConfig.Builder("YOUR_APP_TOKEN")
            .debugLogging(BuildConfig.DEBUG)
            .testMode(BuildConfig.DEBUG)
            .cacheTtlSeconds(120)
            .debugFakeFill(false)
            .build()

        ApexAds.init(this, config)
        WalletAdExtension.install() // Only when the wallet module is included.
    }
}
```

Replace `YOUR_APP_TOKEN` and all demo placement IDs before shipping.

## 4. Create the Flutter bridge

The sample uses two channels:

- `com.apexads.flutter_demo/sdk` for commands such as `loadAd` and `showAd`.
- `com.apexads.flutter_demo/events` for load, impression, click, close, reward,
  auction, and error callbacks.

The Kotlin bridge keeps strong references to active SDK objects. This matters
for asynchronous loads and fullscreen presentation:

```kotlin
private var videoAd: VideoAd? = null

private fun loadVideo() {
    videoAd = VideoAd.Builder("rewarded-placement")
        .listener(object : VideoAdListener {
            override fun onVideoAdLoaded() = emit("video", "loaded", "VAST video ready")
            override fun onVideoAdFailed(error: AdError) = fail("video", error)
            override fun onRewardEarned() = emit("video", "reward", "Reward earned")
        })
        .build()
        .also { it.load() }
}
```

Flutter listens once and stores the latest event for every format:

```dart
static const methods = MethodChannel('com.apexads.flutter_demo/sdk');
static const events = EventChannel('com.apexads.flutter_demo/events');

events.receiveBroadcastStream().listen((event) {
  // Update UI state and append the callback to your diagnostics console.
});

await methods.invokeMethod('loadAd', {'format': 'video'});
```

See `ApexSdkBridge.kt` and `lib/main.dart` for the complete implementation.

## 5. Render SDK-owned views

Banner ads stay inside the Android SDK renderer. Register a platform-view
factory in Kotlin and embed it from Flutter:

```dart
const AndroidView(
  viewType: 'apexads/banner',
  creationParams: {'slot': 'banner', 'mrect': false},
  creationParamsCodec: StandardMessageCodec(),
)
```

Native and conversational responses expose structured assets to Flutter. The
publisher renders them, while the native bridge records rendered state and
routes clicks/actions back through the SDK.

## 6. Load and show correctly

Use one load step and wait for the SDK's loaded callback before presenting a
fullscreen format:

```dart
await methods.invokeMethod('loadAd', {'format': 'interstitial'});
// Enable Show only after event == 'loaded'.
await methods.invokeMethod('showAd', {'format': 'interstitial'});
```

Banner, native, and conversational ads render after loading and do not require a
separate `showAd` call. Rewarded video, interstitial, and wallet interstitial do.

## Demo placements

| Format | Placement ID |
| --- | --- |
| Banner | `demo-banner-placement` |
| Interstitial | `demo-interstitial-placement` |
| Native | `demo-native-placement` |
| Conversational | `demo-assistant-inline` |
| Rewarded video | `demo-video-placement` |
| App open | `demo-appopen-placement` |
| In-app bidding | `demo-inappbidding-placement` |

## Local server routing

Android Emulator uses `10.0.2.2` to reach the host machine. Therefore a debug
SDK configured for `http://10.0.2.2:8080` reaches an ad server listening on
`localhost:8080` on the development computer.

For a physical device, use an HTTPS-accessible server or rebuild the debug SDK
with an address reachable from that device. Never ship a production app with a
local cleartext endpoint.

## Rewarded-video XML compatibility

The bundled video AAR rejects VAST documents containing a `DOCTYPE` before XML
parser construction, then enables external-entity protections on a best-effort
basis. This avoids Android provider differences that can otherwise surface as:

```text
XML parse error: http://apache.org/xml/features/disallow-doctype-decl
```

Safe VAST XML continues to parse, while documents that could enable external
entity expansion remain rejected.

## Troubleshooting

- **Connection refused:** confirm the ad server is listening on port `8080` and
  use `10.0.2.2`, not `localhost`, from an emulator.
- **No fill:** verify the app token, placement, active demand, and auction logs.
- **Show stays disabled:** wait for the `loaded` callback; do not show while a
  request is still loading or after the ad has been consumed.
- **Blank banner:** keep the Android platform view visible and hardware
  acceleration enabled, then check WebView/network logs.
- **Native click does not track:** route both display and click/action signals
  through the native SDK object rather than opening URLs directly in Dart.
- **Rewarded XML feature error:** ensure the fixed `sdk-video` AAR from this
  repository is in the selected build variant.

## Production checklist

- Replace demo tokens and placements.
- Use release AARs and HTTPS demand endpoints.
- Disable debug logging and test mode.
- Configure a release signing key.
- Add consent/privacy flows required for your regions and demand partners.
- Test load, impression, click, close, no-fill, timeout, and reward callbacks.
- Validate ProGuard/R8 and lifecycle behavior on real devices.
