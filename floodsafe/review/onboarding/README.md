# Onboarding artwork review — issue #21

Baseline: `main` at `32e6448`. Final: `design/21-onboarding-illustrations`.
Captures use Flutter widget rendering at device-pixel ratio 1, the app's bundled
Roboto/Lora fonts and Material Icons, with synthetic signed-out account state.
They contain no user data. The Chapter 5 report remains unchanged and image-free.

## Changes and rationale

| Change | Why it helps |
| --- | --- |
| Responsive building density, skyline details and a civic tower silhouette | Keeps recognisable city detail at narrow widths without overcrowding the illustration |
| Soft blue/teal hills, warm sun and separated river | Preserves FloodSafe's palette and gives the scene clearer depth |
| Decoration clipped to its own area and excluded from semantics | Keeps text outside the illustration and avoids distracting screen-reader announcements |
| Artwork below optional account actions | Makes the refinement visible in the current flow while keeping the task controls first |
| Welcome button/divider text can wrap | Fixes the two observed horizontal overflows at 320 px with 200% text |
| Welcome switches to one column with enlarged text | Gives text a usable line width and keeps content/actions scrollable |

Home remains the app's entry point. Account sign-in is optional; the historical
phone welcome/verification preview is not connected to the main flow. Its artwork
and responsive layout are retained for review, without changing authentication.
The landscape is decorative, not a map, flood extent or verified route.

## Before / after previews

| View | Before | After |
| --- | --- | --- |
| Artwork, 320 px | [Before](before/landscape-320.png) | [After](after/landscape-320.png) |
| Artwork, 1000 px | [Before](before/landscape-1000.png) | [After](after/landscape-1000.png) |
| Optional account, 320 px | [Before](before/account-320.png) | [After](after/account-320.png) |
| Optional account, 1000 px | [Before](before/account-1000.png) | [After](after/account-1000.png) |
| Welcome preview, 320 px | [Before](before/welcome-320.png) | [After](after/welcome-320.png) |
| Welcome preview, 1000 px | [Before](before/welcome-1000.png) | [After](after/welcome-1000.png) |

The fixed-height screenshots capture the initial viewport; longer forms remain
scrollable. At 320 px the 200% welcome regression originally reported 30 px and
76 px horizontal overflows. The updated responsive checks verify both welcome
and account actions at 100% and 200% at 320/1000 px widths. These are layout
checks, not a claim that the wider bilingual/accessibility issue #25 is complete.

## Reproduce

From `floodsafe/`, the normal suite runs without writing images:

```bash
flutter test test/onboarding_test.dart
```

To regenerate final previews with the bundled app fonts:

```bash
FLOODSAFE_PREVIEW_DIR="$PWD/review/onboarding/after" flutter test test/onboarding_test.dart
```

Baseline images use the original three UI files from `32e6448` with the same
capture helper, font loading and signed-out fixture. No new image-generation
service or external artwork dependency is required.
