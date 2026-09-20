# Operating Tessera alpha releases

[한국어](RELEASING.md) | English

This guide describes the build, signing, and publication procedure. It is not evidence that these commands
or an actual update installation have passed. It requires macOS, Swift 6, access to the GitHub repository,
releases and Pages, and the login keychain containing Tessera's update key.

## Versions and signing keys

- `TesseraReleaseVersion` in `Resources/Info.plist` is the display version, such as `0.1.0-alpha.4`.
  Prefix it with `v` for the Git tag, and use the full display version in the DMG filename.
- `CFBundleShortVersionString` is the base version, such as `0.1.0`. `CFBundleVersion` is a continually increasing
  integer build number. Updates compare build numbers, so never reuse an earlier number for a new release.
- **Sparkle 2.10.0** is pinned in `Package.swift` and `Package.resolved`. `scripts/sparkle-tools.sh` locates only
  the pinned artifact's tools and checks the version and checksum. Do not mix them with newer signing tools downloaded separately.
- The app and its nested components need ad hoc code signatures, while both the DMG and appcast need Ed25519
  signatures. Update signatures do not replace Apple Developer ID signing or notarization.

### Generate a key only for initial setup

**Skip this step if a key already exists for distributed Tessera versions.** Initial setup happens once,
using the app-specific account `io.github.jgoneit.tessera`.

```sh
swift package resolve
TESSERA_SPARKLE_TOOLS="$(bash scripts/sparkle-tools.sh)"
"$TESSERA_SPARKLE_TOOLS/generate_keys" --account io.github.jgoneit.tessera
```

Respond to any macOS keychain authentication prompt locally. Copy only the printed **public key** into
`SUPublicEDKey` in `Resources/Info.plist`. Keep the private key in the login keychain; never export it to the
repository, release assets, documentation, or logs.

For later releases, look up the existing public key only. The `-p` option does not generate a key.

```sh
TESSERA_SPARKLE_TOOLS="$(bash scripts/sparkle-tools.sh)"
"$TESSERA_SPARKLE_TOOLS/generate_keys" --account io.github.jgoneit.tessera -p
```

`prepare-update.sh` also checks that the existing public key matches the bundle. It stops if the key is missing
or different. Creating a new key to bypass that failure would break trust for apps already installed.

## Prepare a candidate

Run from the repository root. Set the release version and build number first, then prepare Korean and English
release notes in one Markdown file. Replace `TESSERA_RELEASE_NOTES` below with its actual absolute path.

```sh
swift test
bash scripts/build-app.sh
bash scripts/build-dmg.sh --skip-build
TESSERA_RELEASE_NOTES=/absolute/path/to/bilingual-release-notes.md
bash scripts/prepare-update.sh "$TESSERA_RELEASE_NOTES"
```

- `build-app.sh` assembles the executable, resources, and Sparkle framework and helpers into `dist/Tessera.app`.
  It signs nested components outward and checks architectures, links, load paths, and configuration.
- `build-dmg.sh --skip-build` packages the verified bundle without rebuilding. For alpha.4 arm64,
  the result is `dist/Tessera-0.1.0-alpha.4-arm64.dmg`.
- `prepare-update.sh <notes.md>` signs the DMG and feed using the existing key. It embeds bilingual notes
  and creates `website/appcast.xml` and `dist/SHA256SUMS`. The current tool publishes complete DMGs on the
  alpha channel and does not generate delta updates.
- The scripts do not commit to Git, publish releases or Pages, or replace the installed app.
  Changes to source, the app bundle, or the DMG after preparation require rebuilding, verification, and signing again.

The public-key verifier checks the feed and DMG without accessing the keychain.

```sh
swift scripts/verify-update.swift \
  dist/Tessera.app/Contents/Info.plist website/appcast.xml \
  dist/Tessera-0.1.0-alpha.4-arm64.dmg
(cd dist && shasum -a 256 -c SHA256SUMS)
node --test website/*.test.mjs
node --check website/app.mjs
```

`verify-update.swift` checks the feed signature, DMG signature and length, build, and tag-specific download URL.
Omit the DMG argument to verify only the feed. `bash scripts/test-update-verification.sh` tests valid and tampered
inputs with temporary test keys, without requiring the release key. Separately mount the DMG read-only to inspect
the app, Applications link, and bilingual installation guide, then detach it.

## Exercise a real update

Keep the final public DMG unchanged. Create a local source app with an older build number only to start the test.
Prepare the signed final appcast and DMG first, then run:

```sh
bash scripts/prepare-update-test.sh 8769
```

The script prints a fixture path under `dist/.tessera-update-test.<random>/Tessera.app` and a server command.
The fixture lowers the build number, points to a loopback feed, assigns a unique Sparkle `SUDefaultsDomain`, and
turns off automatic checks. It re-signs the test feed with the same key without changing the target DMG's bytes.
Never publish this app, feed, or localhost URL, or distribute the fixture as the installed app.

1. Back up the installed app and user settings, then quit the running Tessera. Do not run the fixture and installed copy together.
2. Start the local server with the printed `python3 -m http.server ... --bind localhost --directory ...` command and open the fixture.
3. Test cancellation and rejection of an invalid feed or tampered DMG. Confirm that the existing app is not replaced.
   Modify copies inside the fixture directory only when constructing failure cases.
4. With the valid test feed and final DMG, download, install, and relaunch. Compare the running app's version and executable hash
   with the final bundle. Separately verify shortcut registration, window placement, preserved settings, and Accessibility permission.
5. Quit test processes and the server, then clean up temporary fixtures, feeds, and test-only Sparkle preferences.
   Do not delete ordinary Tessera settings. Confirm the final app's running path before resuming use of the installed copy.

`SUDefaultsDomain` isolates **Sparkle preferences only**. Grids, theme, and shortcuts share Tessera's bundle identifier,
so back up settings and compare them afterward. The final app must not contain a test feed, test domain, or ATS exception.
Code-signature verification does not prove successful installation, Accessibility approval, or Gatekeeper acceptance on another Mac.

## Publish and recover

1. Align the Korean/English README, installation guides, and website links with the final version and filename. Commit source,
   documentation, and the signed appcast by purpose. Run PR checks and the corresponding Seal Task's `verify`, followed by
   `complete` with the exact returned Run ID.
2. Create a prerelease such as `v0.1.0-alpha.4` from the **exact verified source commit**. Attach the final DMG and
   `SHA256SUMS`, preserving existing releases and assets.
3. Download both public assets again and verify their checksum and signature. Do not publish a feed pointing to unavailable assets.
4. Merge the PR to deploy Pages and verify the signature at `https://jgoneit.github.io/tessera/appcast.xml`.
   Check public Korean/English download links and a manual update check in the installed app.
5. Record actual results and untested scenarios in both languages. Retain the notice that **alpha.3 and earlier have no updater
   and require a one-time manual alpha.4 installation**.

Never directly edit and publish a signed appcast. Stage any change, sign it again using the existing key, and deploy only after
public-key verification. To withdraw a bad update, remove its item from the feed and re-sign the feed. Repair an already installed
version by releasing a **higher build number**; automatic downgrades are not provided. Do not silently replace a published DMG
under the same name. Use the backed-up app for manual local recovery, and account for possible Accessibility renewal after an
ad hoc signature change.
