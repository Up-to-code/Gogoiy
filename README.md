# Gogoiy

Gogoiy is an original, native iOS block-placement puzzle built with SwiftUI and
SpriteKit. It supports iPhone and iPad in portrait and landscape and targets
iOS 17 or newer.

## Run

1. Open `Gogoiy.xcodeproj` in Xcode 26 or newer.
2. Select the `Gogoiy` scheme and an iPhone or iPad simulator.
3. Build and run.

The game stores the best score and audio/haptic preferences in `UserDefaults`.
Google Mobile Ads 13.6.0 is integrated through Swift Package Manager, with UMP
consent requested before ads are loaded.

Debug builds use Google's official test application and ad-unit IDs. Release
builds use the Gogoiy production AdMob application ID, Home Banner unit, and
Power-Up Reward unit. Do not replace the debug IDs with live IDs while testing.

Ads are limited to a compact banner on the home screen and a rewarded Hint that
the player explicitly requests. Gameplay is never interrupted by an automatic
interstitial.

## Tests

Run the `GogoiyTests` target with Product → Test, or:

```sh
xcodebuild test \
  -project Gogoiy.xcodeproj \
  -scheme Gogoiy \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```
