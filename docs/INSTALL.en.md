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

Tessera is a **menu bar app with no Dock icon**. Click the three-pane icon on the right side of the menu bar
to access Settings, window placement, and Quit. The absence of a Dock icon after launch does not indicate an installation failure.

## Install from a DMG

1. Double-click `Tessera-<version>-<architecture>.dmg`.
2. Drag `Tessera.app` inside the disk image onto the adjacent **Applications** folder.
   Quit any running Tessera first and keep any previous version you need before replacing it.
3. Once copying finishes, eject the Tessera disk in Finder.
4. Launch Tessera from the Applications folder. Do not keep running the copy inside the disk image.

The DMG contains `Tessera.app`, a link to `/Applications`, and a Korean/English `INSTALL.txt`.
It does not install automatically or change permissions.

## Check permission to move windows

1. Click **Open Settings** in Tessera Settings.
2. Under **System Settings → Privacy & Security → Accessibility**, allow **Tessera at its installed location**.
   If it is missing, click `+` and select `/Applications/Tessera.app` or the app at the location you actually copied it to.
3. Click the refresh button (**Check Again**) in Tessera Settings to confirm it is ready.
4. Activate a regular window in another app and use your existing direction shortcuts to place it.

Moving the app from a development folder to Applications or rebuilding an ad hoc app may require checking Accessibility
permission again. If System Settings shows permission enabled but Tessera still requests access, remove only the old Tessera
entry, add the **currently installed app** again, and restart Tessera to check. Leave other apps' permissions unchanged.
Grids, spacing, language, theme, and shortcuts use the existing settings for the same user account.

## Create a local DMG

Run this command from the repository root. By default, it builds the release app before packaging it.

```sh
bash scripts/build-dmg.sh
```

To package an already verified `dist/Tessera.app` without rebuilding or signing it again, use:

```sh
bash scripts/build-dmg.sh --skip-build
```

The filename comes from the app bundle's version and the executable's actual architecture.
For example, version 0.1.0 with an arm64 executable produces `dist/Tessera-0.1.0-arm64.dmg`.
The script checks the app's code signature and repeats the check on the bundle copied to a temporary folder.
It creates a UDZO compressed image with `hdiutil create`, checks the image checksum with `hdiutil verify`,
then places it at the final path. An existing DMG with the same name is replaced only after the new image passes verification.
Temporary files are cleaned up on failure or interruption.

These checks do not prove actual window movement, Accessibility approval, Gatekeeper approval, or successful notarization.
Mounting the image, installing the app, and launching it are separate steps that the script does not perform automatically.

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
- Tessera lives in the menu bar and has no Dock icon. Allow the installed app in
  **System Settings → Privacy & Security → Accessibility**, then use **Check Again** in Tessera Settings.
- Run `bash scripts/build-dmg.sh` to build and package, or add `--skip-build` to package an existing verified bundle.
  Output is `dist/Tessera-<version>-<architecture>.dmg`.
- This is a local ad hoc build without Developer ID signing or Apple notarization. A DMG does not replace
  notarization or grant permission to run. Installation and packaging do not change macOS security settings.
