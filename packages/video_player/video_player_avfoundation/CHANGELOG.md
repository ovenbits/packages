## 2.10.4

- Fixes unwanted automatic Picture-in-Picture on iOS for texture players when
  `allowAutoPictureInPicture` is false by not creating an
  `AVPictureInPictureController` until automatic or manual PiP is requested.

## 2.10.3

- Adds creation-time `allowAutoPictureInPicture` support via `VideoCreationOptions`.
- Fixes `setAutoPictureInPicture` being ignored when called before the PiP
  controller is created by storing and applying the preference at setup time.

## 2.10.2

- Fixes macOS build error caused by `canStartPictureInPictureAutomaticallyFromInline` being unavailable on macOS.

## 2.10.1

- Fixes CarPlay Now Playing play/pause button not updating when playback is controlled from the Flutter app.

## 2.10.0

- Adds background playback with system media notification support.
- Adds Picture-in-Picture (PiP) support for iOS and macOS.

## 2.9.7

- Forces tone-mapping to SDR on iOS to prevent washed-out HDR video playback.

## 2.9.6

- Adds a Swift version to fix a potential build issue when using CocoaPods.

## 2.9.5

- Converts portions of the native code to Swift for improved maintainability.

## 2.9.4

- Ensures that the display link does not continue requesting frames after a player is disposed.

## 2.9.3

- Fixes a regression where HTTP headers were ignored.

## 2.9.2

- Refactors for improved testability.

## 2.9.1

- Refactors native code for improved testability.

## 2.9.0

- Implements `getAudioTracks()` and `selectAudioTrack()` methods.
- Updates minimum supported SDK version to Flutter 3.29/Dart 3.7.

## 2.8.10

- Improves compatibility with `UIScene`.
- Updates minimum supported SDK version to Flutter 3.38/Dart 3.10.

## 2.8.9

- Resolve `tracksWithMediaType:` deprecations.
- Use `loadTracksWithMediaType:completionHandler:` for iOS 15.0+/macOS 12.0+.

## 2.8.8

- Refactors Dart internals for maintainability.

## 2.8.7

- Updates to Pigeon 26.

## 2.8.6

- Fixes a bug where the video player fails to initialize when `AVFoundation` reports a duration of zero.
- Fixes a bug in the example app that some widgets stop updating after GlobalKey reparenting.
- Updates the `VideoProgressIndicator` widget in the example app to handle zero-duration videos.

## 2.8.5

- Updates minimum supported version to iOS 13 and macOS 10.15.
- Updates minimum supported SDK version to Flutter 3.35/Dart 3.9.

## 2.8.4

- Simplifies native code.
