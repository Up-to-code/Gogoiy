# Gogoiy

Gogoiy is an original, native iOS block-placement puzzle built with SwiftUI and
SpriteKit. It supports iPhone and iPad in portrait and landscape and targets
iOS 17 or newer.

## Run

1. Open `Gogoiy.xcodeproj` in Xcode 26 or newer.
2. Select the `Gogoiy` scheme and an iPhone or iPad simulator.
3. Build and run.

The game stores the best score and audio/haptic preferences in `UserDefaults`.
Unity Ads 4.19.0 is integrated through Swift Package Manager. The app sends
restrictive privacy signals and does not request cross-app tracking permission.

The Unity dashboard app is configured with Game ID `800109658`, banner placement
`Banner_iOS`, and rewarded placement `Rewarded_iOS`. These values are set in the
Gogoiy target's build settings as `UNITY_ADS_GAME_ID`,
`UNITY_ADS_BANNER_PLACEMENT_ID`, and `UNITY_ADS_REWARDED_PLACEMENT_ID`.

Unity Ads test mode is always enabled in Debug builds and disabled in Release.
Never exercise live production inventory during development.

Ads are limited to a compact banner on the home screen and a rewarded Hint that
the player explicitly requests. Gameplay is never interrupted by an automatic
interstitial.

## Tests

Run the `GogoiyTests` target with Product → Test, or:

```sh
xcodebuild test \
  -project Gogoiy.xcodeproj \
  -scheme Gogoiy \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```
