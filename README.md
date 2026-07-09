# Toddler Coder for Mac

A native macOS full-screen keyboard-mashing game. It makes random keypresses look like a tiny coding workspace while trying to keep normal kid-mode keyboard input inside the app.

## For Your Mac Friend

1. Download `ToddlerCoder-Mac.zip` from the latest GitHub Actions build or release.
2. Double-click the zip to unzip it.
3. Double-click `ToddlerCoder.app`.
4. If macOS asks for permission to monitor input or accessibility, allow it in System Settings, then reopen the app.

The app opens in full-screen kid mode by default. To exit, hold `Control+Shift+Q` for 3 seconds.

## Important macOS Note

Toddler Coder uses native macOS kiosk presentation options and a Quartz event tap for keyboard guarding. macOS requires the user to approve input monitoring/accessibility permission before any app can globally intercept keyboard events. Without that permission, the app still captures normal keypresses while focused, but macOS-level shortcuts may escape.

On a first launch without permission, Toddler Coder intentionally does not enable the strictest kiosk presentation options, so an adult can still switch to System Settings and grant access. After permission is granted, reopen the app for the locked kid-mode run.

No unsigned app can bypass Gatekeeper, Input Monitoring, Accessibility, Force Quit, or power controls perfectly. For a true one-click app with no security prompts, the app would need to be signed and notarized with an Apple Developer ID.

## Build on a Mac

```bash
bash scripts/build-mac-app.sh
open dist/ToddlerCoder.app
```

## Debug Windowed Mode

From a Mac terminal:

```bash
dist/ToddlerCoder.app/Contents/MacOS/ToddlerCoder --debug-windowed
```

Debug mode opens a normal resizable window and does not install the global keyboard guard.
