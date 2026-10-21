# Developing OpenBar

OpenBar is a Swift package (AppKit + SwiftUI) with no Xcode project.

## Requirements

- macOS 26
- Swift 6.2 or later (Command Line Tools are enough for local builds; universal builds need Xcode)

## Build and run

```bash
./scripts/build-app.sh            # build/OpenBar.app for this Mac's architecture
open build/OpenBar.app

UNIVERSAL=1 VERSION=1.2.0 ./scripts/build-app.sh   # arm64 + x86_64, with a version number
./scripts/make-dmg.sh                               # build/OpenBar-<version>.dmg
```

### Keeping permissions across rebuilds

macOS ties Accessibility and Screen Recording grants to the app's code signature. Ad-hoc signing produces a new signature every build, so grants are lost each time. Create a local self-signed identity once:

```bash
./scripts/create-signing-cert.sh
```

`build-app.sh` picks it up automatically. To use a different identity, set `SIGN_IDENTITY`.

## Releasing

Push a tag:

```bash
git tag v1.2.0 && git push origin v1.2.0
```

The `Release` workflow builds a universal app, signs it, packages a DMG, publishes a GitHub release and bumps the cask in [saenai255/homebrew-tap](https://github.com/saenai255/homebrew-tap).

Repository secrets:

| Secret | Purpose |
| --- | --- |
| `SIGNING_P12` | Base64 of the "OpenBar Release Signing" identity (.p12). It must stay the same across releases so users keep their permission grants after updating. |
| `SIGNING_P12_PASSWORD` | Password for that .p12. |
| `TAP_TOKEN` | Fine-grained token with Contents read/write on `saenai255/homebrew-tap`. Without it, the workflow prints the new version and sha256 to update the cask by hand. |

## Layout

```
Sources/OpenBar/
  AppDelegate.swift        app lifecycle, one bar per display, settings window
  Prefs.swift              settings, stored in UserDefaults
  Model/TaskbarModel.swift running apps, windows, ordering, click behaviour
  System/                  Accessibility, Dock, power, audio, battery, previews
  UI/                      bar panel, buttons, tray, previews, menus, settings
design/icon.swift          draws the app icon; `swift design/icon.swift out.png 1024`
```

## How it works

| Concern | Mechanism |
| --- | --- |
| Window list | `AXWindows` per app, `_AXUIElementGetWindow` for the `CGWindowID` |
| Focus / minimize / close | `AXRaise`, `AXMain`, `AXMinimized`, close-button `AXPress` |
| Badges | The Dock's accessibility tree, `AXStatusLabel` on each item |
| Previews | `SCScreenshotManager.captureImage` |
| Keeping windows clear | `AXObserver` for window created/moved/resized; frames clamped to the usable area |
| Hung apps | WindowServer notifications 750/751 and `CGSEventIsAppUnresponsive` |
| Show Desktop | `CoreDockSendNotification("com.apple.showdesktop.awake")` |
| Lock screen | `SACLockScreenImmediate` from `login.framework` |
| Power actions | Apple Events to `loginwindow` |
| Dock-less mode | `com.apple.dock` `autohide-delay` set very high, previous values restored on disable |

## Diagnostics

`open -n build/OpenBar.app --args --probe-dock /tmp/dock.log 12` logs the Dock's accessibility attributes and notifications for 12 seconds, then exits.
