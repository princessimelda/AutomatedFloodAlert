# FloodSafe

Flutter interface prototype for flood awareness in Nairobi. The English-language demonstration includes phone verification, an illustrative risk map, route previews, a news feed, and a scripted assistant.

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

1. Enter sample number `712345678` and verification code `123456`, or select **Explore the demo first**.
2. Select a sample Nairobi location, explore the risk layers, and preview a route.
3. Open **Flood News** to filter and read sample stories.
4. Open **AI Assistant** to try the scripted responses.

## Implementation and status

Built with Flutter and Dart, Material widgets, custom map illustrations, and bundled Lora and Roboto fonts. Font licenses are included in `assets/fonts/`.

All weather, risk, route, and news content is illustrative. SMS, authentication, GPS, database integration, model inference, live AI, and notifications are not implemented. Routes are not intended for navigation.

Static analysis, five interaction and layout tests, and the web build passed during prototype development. Android device builds have not yet been verified. Screen captures are available in [docs/previews](docs/previews/).

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
