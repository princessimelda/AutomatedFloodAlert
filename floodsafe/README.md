# FloodSafe

Flutter application in development for flood awareness in Nairobi. The current local version opens directly to a location → situation → preparedness flow, without requiring sign-in. It supports either explicit standalone fixtures or a Python API backed by PostgreSQL/PostGIS. Current development examples are not live predictions.

## Connected development

Start the API using the [backend instructions](../backend/README.md), then run:

```sh
flutter run -d web-server --web-hostname=127.0.0.1 --web-port=8765 --dart-define=FLOODSAFE_API_URL=http://127.0.0.1:8000
```

The place picker, dashboard assessment and published advisories use backend responses. API errors do not fall back to sample risk. The only configuration passed to Flutter is the API URL; database passwords stay server-side. Without the define, the app retains standalone demo mode. A current local test preview may use API port 8001; use that port in the define when testing that server.

The downloadable 0.1.0 APK below is the earlier prototype. It does not contain the local core-flow changes described here.

## Android APK

[Download FloodSafe for Android](https://github.com/princessimelda/AutomatedFloodAlert/raw/refs/heads/main/floodsafe/downloads/FloodSafe-0.1.0.apk)

Requires Android 7.0 or newer. Download the APK on your Android phone, open it, and allow installation from your browser or file manager if Android asks. The installed demo works without a local server and uses illustrative data and scripted interactions.

Version 0.1.0 is a release-mode demonstration APK signed with a development key. The Android build and APK signature verification passed, along with all five Flutter tests. It is intended for direct installation and testing, not Play Store distribution. It has not been tested on a physical Android device. The download checksum is in [downloads/SHA256SUMS](downloads/SHA256SUMS).

## Local demonstration

[Open the FloodSafe demonstration](http://127.0.0.1:8765)

From the `floodsafe` directory, start the application:

```sh
flutter pub get
flutter run -d chrome --web-port=8765 --web-hostname=127.0.0.1
```

Keep the terminal running during the demonstration. The link works only on the computer running the application; it is not a publicly hosted website. If port 8765 is already in use, stop the previous demo server first.

In VS Code, open this folder, select **FloodSafe - Chrome demo**, and press **F5**.

## Demonstration flow

1. Home opens without an assumed location. Read general preparedness steps at any time using the persistent action button.
2. Select **Choose a place** to explore labelled scenarios: Kibera (sample high risk), Kasarani (sample low risk), Westlands (unavailable), and Embakasi (expired information). These scenarios do not describe actual conditions in those places.
3. Alternatively, select **Use my location** for a one-time foreground fix. Standalone demo mode keeps coordinates in memory. In API mode, coordinates are sent in a dashboard POST body for a spatial lookup, not saved or put in request URLs. Demo polygons never match real GPS coordinates; without a published non-demo assessment the result is unavailable.
4. **Open map** shows an interactive OpenStreetMap view, device-location accuracy and saved neighbourhoods. Place markers are approximate centres, not flood boundaries or safe destinations. See [maps](docs/maps.md). **Help** contains the database-backed guided assistant when the API is configured; otherwise it shows an empty catalogue. Sample Flood News is hidden. See [guided assistant](docs/guided-assistant.md).
5. The profile button opens optional Supabase email sign-in and saved places. Configure the public project URL and publishable key first; guest access remains available without them. See [accounts and saved places](docs/accounts.md).

GPS on web requires HTTPS or localhost and browser permission. Denied, disabled, inaccurate, stale, or timed-out fixes leave manual selection and preparedness guidance available. Background tracking is not implemented.

See [the core-flow implementation notes](docs/core-flow.md) for state rules, issue mapping, verification, and remaining work.

## Implementation and status

Built with Flutter and Dart, Material widgets, custom map illustrations, and bundled Lora and Roboto fonts. Font licenses are included in `assets/fonts/`.

All seeded risk, map, route, and news examples are illustrative. Foreground location access and public-read backend integration are implemented. Real authentication/SMS, model inference, live AI, notifications, background location, and offline persistence are not implemented. The earlier route preview is no longer offered as a Home-screen action. No verified route or evacuation destination is provided.

The core has controller, location-service, and widget tests covering data validity, request ordering, GPS fallback, enlarged text, and automated Home-screen accessibility checks. These checks do not replace physical-device, screen-reader, or user usability testing. Screen captures in [docs/previews](docs/previews/) show the earlier prototype.

## Validation

```sh
flutter analyze
flutter test
flutter build web --no-web-resources-cdn
```

## Chrome connection troubleshooting

If Flutter cannot connect to Chrome, stop the current run before retrying. Cloud-backed files in `.dart_tool/chrome-device` can delay restoration of Flutter's generated browser profile. Back up and rename that cache while Flutter is stopped to allow a fresh profile to be created. This does not affect the normal Chrome profile.

For a presentation without Chrome debugger attachment, select **FloodSafe - Browser demo (no Chrome debugger)** in VS Code, or run:

```sh
flutter run -d web-server --web-port=8765 --web-hostname=127.0.0.1
```

Wait for the server-ready message, then open the [local demonstration](http://127.0.0.1:8765) manually. Use only one launch session on port 8765 at a time.
