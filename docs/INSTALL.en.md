# Install Tessera locally

[한국어](INSTALL.md) | [English](INSTALL.en.md)

You can build Tessera yourself and install it in the Applications folder on your own Mac without joining the Apple Developer Program.
The current build uses local **ad hoc signing** and does not include Developer ID signing or Apple notarization.
A DMG is a disk image that makes copying the app convenient; it does not replace notarization.
See [Apple's membership comparison](https://developer.apple.com/support/compare-memberships/) for the capabilities available
for development, personal device testing, Developer ID signing, and notarization.

Requires macOS 14 or later. The default build targets **only the architecture of the Mac that builds it**;
it does not produce a universal app or cross-compile. For example, an `arm64` app built on Apple Silicon has not thereby
been verified to run on Intel Macs.

The current release is **0.1.0-alpha.4**. Download
[`Tessera-0.1.0-alpha.4-arm64.dmg`](https://github.com/jgoneit/tessera/releases/download/v0.1.0-alpha.4/Tessera-0.1.0-alpha.4-arm64.dmg)
for Apple Silicon. **If you use alpha.3 or earlier, install this DMG manually once to enable future updates inside the app.**

## Install the app directly

1. To build from source, install Swift 6 or later and the macOS SDK, then run this command from the repository root:

   ```sh
   bash scripts/build-app.sh
   ```

2. If Tessera is running, choose **Quit Tessera** from its menu bar icon.
3. In Finder, copy `dist/Tessera.app` to **Applications** (`/Applications`).
   If replacing an existing version, keep a backup elsewhere first. Finder may ask for permission to write to the folder.
   You can also copy it to `~/Applications` if you use a personal Applications folder.
4. Launch `Tessera.app` from the location you copied it to. Use this installed copy from now on.

Tessera is a **menu bar app**. Click the three-pane icon on the right side of the menu bar to access Settings,
window placement, and Quit. Opening Settings or an update window shows its window in Mission Control and its app icon in the Dock and ⌘Tab.
The app icon remains when Settings is minimized or behind another app. Closing both Settings and the update window returns Tessera
to menu bar-only mode while the app keeps running. Showing only the picker or placement feedback does not add a Dock icon.

## Install from a DMG

1. Double-click `Tessera-<version>-<architecture>.dmg`.
2. Drag `Tessera.app` inside the disk image onto the adjacent **Applications** folder.
   Quit any running Tessera first and keep any previous version you need before replacing it.
3. Once copying finishes, eject the Tessera disk in Finder.
4. Launch Tessera from the Applications folder. Do not keep running the copy inside the disk image.

The DMG contains `Tessera.app`, a link to `/Applications`, and a Korean/English `INSTALL.txt`.
It does not install automatically or change permissions.

## Update Tessera

Starting with alpha.4, use **Check for Updates…** in the menu or Settings.
Settings shows the installed full release version, such as `0.1.0-alpha.4`.

1. Choose **Check for Updates…**. Checking, up-to-date, and failed checks have distinct states.
2. If a new version is available, read the version and changes, then choose **Install**.
3. Tessera downloads the update, verifies its signature, replaces the app, and relaunches it. Your grids, spacing, language, theme, and shortcuts are preserved.
4. If window placement needs permission again, follow the Accessibility steps below.

Automatic checking is **on by default, once a day**, and can be disabled in Settings. Manual checks remain available.
Background checks show **New version available** in the menu and Settings without opening a window or taking focus.
Tessera does not automatically download or install updates before you choose to install. Failed checks leave your installed app
and window placement available. Alpha apps check for alpha and stable releases; stable apps check for stable releases only.
Tessera's status messages follow your selected Korean/English app language; Sparkle's standard installation dialogs use macOS's preferred language.

alpha.3 and earlier have no updater, so install the new DMG manually once. Manual replacement from a DMG remains available later.
Do not run a development copy and the installed app at the same time.

## Check permission to move windows

1. Click **Open Settings** in Tessera Settings.
2. Under **System Settings → Privacy & Security → Accessibility**, allow **Tessera at its installed location**.
   If it is missing, click `+` and select `/Applications/Tessera.app` or the app at the location you actually copied it to.
3. Click the refresh button (**Check Again**) in Tessera Settings to confirm it is ready.
4. Activate a regular window in another app and use your existing direction shortcuts to place it.

Moving the app from a development folder to Applications or rebuilding/updating an ad hoc app may require checking Accessibility
permission again. If System Settings shows permission enabled but Tessera still requests access, remove only the old Tessera
entry, add the **currently installed app** again, and restart Tessera to check. Leave other apps' permissions unchanged.
Grids, spacing, language, theme, and shortcuts use the existing settings for the same user account.

## Maximize and screen halves

The default **⌃⌥Return** shortcut maximizes the current window to the area available around the menu bar and Dock,
without a gap. You can also use **Maximize** in the menu or picker. Repeating it keeps the window maximized;
it does not enter macOS full-screen Spaces.

From maximized, **⌃⌥↑ / ⌃⌥↓** moves to the screen's top or bottom half. Down from the top half or up from the bottom
half returns to maximized. **⌃⌥← / ⌃⌥→** enters a column in your selected grids while preserving the height selection.
Screen halves use your configured gap. If the maximize shortcut cannot be registered during migration, the existing
direction shortcuts stay active and Settings shows a notice; the menu and button remain available.

## Create a local DMG

Run this command from the repository root. By default, it builds the release app before packaging it.

```sh
bash scripts/build-dmg.sh
```

To package an already verified `dist/Tessera.app` without rebuilding or signing it again, use:

```sh
bash scripts/build-dmg.sh --skip-build
```

The filename comes from the app bundle's full release version and the executable's actual architecture.
For example, release 0.1.0-alpha.4 with an arm64 executable produces `dist/Tessera-0.1.0-alpha.4-arm64.dmg`.
The script checks the app's code signature and repeats the check on the bundle copied to a temporary folder.
It creates a UDZO compressed image with `hdiutil create`, checks the image checksum with `hdiutil verify`,
then places it at the final path. An existing DMG with the same name is replaced only after the new image passes verification.
Temporary files are cleaned up on failure or interruption.

These checks do not prove actual window movement, Accessibility approval, Gatekeeper approval, or successful notarization.
Mounting the image, installing the app, and launching it are separate steps that the script does not perform automatically.

Publishing updates requires a Sparkle Ed25519 signature in addition to the app's code signature. The same DMG serves
both direct downloads and app updates on GitHub Releases. The signed update feed is published at
`https://jgoneit.github.io/tessera/appcast.xml` on GitHub Pages. The update private key stays in the local login keychain,
never in the repository or release. Creating a local DMG does not publish an update feed or notify existing users.

## Signing and distribution scope

Ad hoc signing with `codesign --sign -` differs from distribution signing with a Developer ID certificate.
Gatekeeper may display a warning when the app is transferred to another Mac or downloaded from the internet.
The current DMG is not guaranteed to run without warnings on every Mac. If macOS blocks it, check the app's source
and the system's instructions. This installation procedure does not change security check settings.
See [Apple's distribution signing guide](https://developer.apple.com/developer-id/) for Developer ID signing and
notarization when preparing a general release.

## Quick guide

- Requires macOS 14 or later. The default build targets the current Mac's architecture only.
- Quit the running Tessera, keep any older app you need, and copy `Tessera.app` to Applications.
  For a DMG, drag the app onto its Applications link, eject the disk, and open the installed copy.
- Tessera lives in the menu bar. Opening Settings or an update window shows its window in Mission Control and its icon in the Dock and ⌘Tab.
  The app icon remains while Settings is minimized or behind another app; closing both windows returns to menu bar-only mode.
- From alpha.4, use **Check for Updates…** in the menu or Settings. Automatic checks run quietly once a day by default; installation requires your action.
  alpha.3 and earlier need one manual DMG installation first. Updating may require renewing Accessibility permission.
- Allow the installed app in **System Settings → Privacy & Security → Accessibility**, then use **Check Again** in Tessera Settings.
- Use **⌃⌥Return** to maximize, then **⌃⌥↑ / ⌃⌥↓** for screen halves or **⌃⌥← / ⌃⌥→** to enter a selected grid.
- Run `bash scripts/build-dmg.sh` to build and package, or add `--skip-build` to package an existing verified bundle.
  Output is `dist/Tessera-<version>-<architecture>.dmg`.
- This is a local ad hoc build without Developer ID signing or Apple notarization. A DMG does not replace
  notarization or grant permission to run. Installation and packaging do not change macOS security settings.
