# Gogoiy App Store submission

## URLs

- Privacy Policy URL: https://gogoiy.qentrah.com/privacy
- User Privacy Choices URL: https://gogoiy.qentrah.com/privacy-choices
- Support URL: https://gogoiy.qentrah.com/support
- Terms URL: https://gogoiy.qentrah.com/terms
- Marketing URL: https://gogoiy.qentrah.com

These custom-domain URLs are live and verified over HTTPS.

## App identity

- App name: Gogoiy
- Bundle ID: com.gogoiy.game
- Category: Games — Puzzle
- Minimum iOS version: iOS 17
- Devices: iPhone and iPad
- Monetization: Unity Ads banner and optional rewarded ads
- Accounts: none
- In-app purchases: none

## App privacy draft

Apple requires the final answers to include data processed by Unity Ads. Review
the current Unity Ads privacy survey before submitting. Based on Unity's current
SDK disclosure, expect to declare at least:

- Coarse location — third-party advertising and analytics
- User ID — app functionality
- Device ID — third-party advertising and analytics
- Purchase history — third-party advertising and analytics
- Product interaction — third-party advertising and analytics
- Advertising data — third-party advertising and analytics
- Other usage data — third-party advertising and analytics
- Performance data — app functionality and analytics
- Other data such as device language, model, screen size, and connection type —
  app functionality, third-party advertising, and analytics
- Customer support — app functionality, if a user contacts support or reports an ad

The app does not request App Tracking Transparency permission and configures
Unity Ads for non-behavioral ads with an opt-out signal. Confirm the correct
"Data Used to Track You" answers against the exact production configuration in
App Store Connect; do not claim that the app collects no data.

## Before uploading

1. Confirm the Apple Developer agreements, tax, and banking sections are active.
2. Create the App Store Connect app record using bundle ID com.gogoiy.game.
3. Verify the final app name and subtitle availability.
4. Add the live privacy, privacy choices, support, terms, and marketing URLs.
5. Complete the App Privacy questionnaire using the current Unity disclosures.
6. Add the App Store listing ID to the Unity dashboard.
7. Test Unity Ads on a physical device using test mode.
8. Archive a Release build and validate it in Xcode Organizer.
9. Upload screenshots for every required iPhone and iPad display size.
10. Complete age rating, content rights, export compliance, review notes, and
    advertising disclosures.
11. Upload the build, select it for the version, and submit for review.

## Current readiness (August 5, 2026)

- Privacy/support site: deployed and verified over HTTPS (all pages return 200).
- In-app Privacy Policy, Terms of Use, Ad Privacy Choices, and Website links point
  to the live site (https://gogoiy.qentrah.com).
- Unity Ads: SDK initializes and loads the banner and rewarded placements in Debug
  (test mode) and Release (live) builds.
- Release simulator build: succeeds.
- Automated tests: 15 passed, 0 failed.
- App icon: 1024 × 1024 asset present.
- Repository: private on GitHub.
- Remaining signing blocker: no Apple Development Team is selected in the Xcode
  project yet. Select the correct paid Apple Developer team before creating the
  distribution archive.
