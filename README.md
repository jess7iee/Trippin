# Trippin
Plan trips, save reservations, optimize routes, give recommendations

An iOS app (SwiftUI + SwiftData, iOS 17+, iPhone and iPad).

## Features
- **Pages per trip:** Summary, then Day 1, Day 2, … (tap a chip or swipe).
- **Reservations from email:** paste a confirmation email in the app, or select its text in Mail/Gmail and choose Share → Trippin. Each booking is placed on its day(s) and found on the map. With a Claude API key, Claude reads the email (good for multi-flight itineraries); without one, an on-device parser does.
- **Maps:** a map of the whole trip and a routed map for each day, with walking or driving times between stops. Tap any pin or place to open it, or get directions, in **Apple Maps, Google Maps or Amap**. If an app isn't installed, its website opens instead.
- **Recommendations:** add what you want or need to do on the Summary page. Claude suggests real places, checks each one in Apple Maps and assigns it to the day where it fits best.
- **Local-language names:** each place also shows its name and address the way they're written locally (浅草寺, 新宿駅, 東京都台東区浅草2丁目3-50), and the open-in-maps menu has a large "Show in local language" card to show a taxi driver. Addresses come from Apple's geocoder. Names come from Claude when a key is set. Amap searches with the local name.
- **Editing:** tap a stop to rename it, add a note, give it a time, move it to another day or point it at a different place. Tap a reservation to fix its details. Its stops move to the matching days and keep their notes. Bookings without an email can be typed in from Add reservation → Enter details yourself.
- **Route optimization:** reorders a day's stops to cut travel. Bookings with a set time stay in time order.

## Project layout
| Folder | What's in it |
|---|---|
| `Trippin/` | App target: models, views, services (Claude client, maps launcher, place search) |
| `Shared/` | Code used by the app, the share extension and the tests (email parser, route optimizer, share inbox) |
| `TrippinShare/` | Share extension that hands emails to the app through the App Group |
| `TrippinTests/` | Swift Testing unit tests for the parser and optimizer |
| `Config/` | Info.plist additions and entitlements |

## Running
Open `Trippin.xcodeproj` in Xcode and run the **Trippin** scheme. To run on a device, set your team under Signing & Capabilities for both the `Trippin` and `TrippinShare` targets. The App Group `group.com.jess7iee.trippin` must be enabled for both.

Debug builds accept the launch arguments `-seedDemo`, which loads a sample Tokyo trip, `-openDemoPage N`, which opens page N (`-1` is Summary), and `-openDemoEditor N`, which opens the editor for stop N on that day (or reservation N on Summary).

Recommendations need a Claude API key (Settings → Claude). The key is kept in the Keychain and sent only to `api.anthropic.com`. Before an App Store release, move these calls behind a small backend so the app doesn't depend on each user having their own key.
