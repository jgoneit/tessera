# Tessera automatic update validation — alpha.4

[한국어](updater-validation.md) | English

Recorded on 2026-09-20 for `0.1.0-alpha.4` / build `4`, using Sparkle `2.10.0`.
Automated checks, offscreen rendering, real local updates, and public/install verification are distinguished below.
Release/Pages publication, update checking in the installed app, and Accessibility-ready status have been confirmed.
The user's physical-shortcut placement check is pending; this is not a claim that overall v0.1 is complete.

## Automated checks and rendering

- **170 Swift tests** passed with rendering enabled, including 3 render tests. Coverage includes version metadata,
  update states, duplicate checks, preferences across restart, quiet scheduled checks, the Settings/update-window
  app-presentation lifetime, and existing window-placement regression cases.
- **13 signature-verifier regression cases** passed using public-key verification. They cover a valid feed/archive
  and feed-only verification; rejection of trailing signature-block data, tampered feed/archive, another key,
  local URLs, mismatched release URLs, missing current build, mismatched length, absent alpha channel,
  incomplete display version, and duplicate build items. Test keys are separate from the release key.
- Rendered available, checking, up-to-date, and offline states in Korean/English × light/dark, including the long
  `0.1.0-alpha.100` label at default 680×800pt, minimum 640×620pt, and full-scroll 640×1680pt sizes.
  Offscreen rendering does not establish physical key input, clicks, focus changes, or VoiceOver behavior.

## Real Sparkle local update

The alpha.4 candidate DMG was left unchanged. A separate fixture with its build number
lowered to `3` used a loopback feed. A unique `SUDefaultsDomain` isolated Sparkle preferences; ordinary Tessera
settings were separately preserved and compared.

| Scenario | Observed result |
| --- | --- |
| Invalid unsigned feed | Sparkle rejected it with an error dialog without proceeding to installation |
| Corrupted DMG | Signature verification rejected it after downloading and before installation |
| Cancel or close | The fixture remained at build 3 with the same executable hash |
| Valid update | Downloading the candidate DMG and choosing Install & Restart replaced and relaunched the fixture as alpha.4 |
| Relaunched bundle configuration | The public `SUFeedURL` was restored, with no test `SUDefaultsDomain` |
| Framework loading | `vmmap` confirmed Sparkle loaded from inside the running app bundle |

After the first test, packaging was amended to include Sparkle license resources without changing runtime source.
The successful update and relaunch test was repeated with this final DMG. The executable SHA-256 matched the final
`dist/Tessera.app`, and signature verification passed for the final appcast and DMG.

| Final artifact | SHA-256 |
| --- | --- |
| App executable | `3499da2c3f96e3159cb6ae40d44f5e267a8164add0235e42550d1cdf049125c7` |
| `Tessera-0.1.0-alpha.4-arm64.dmg` | `02b798a657f5b52e3a12ab6501a5a6144350eb12c7ed04adf005a5e61ba1f5ee` |

The original alpha.3 at `/Applications/Tessera.app` was not replaced during these tests. Its executable retained
SHA-256 `dce6b39f41b283f4696beedb76f1719907f71bf487740a87f987141bf9e1db67`.
Results from this test copy remain distinct from the later final `/Applications` installation recorded below.
They do not establish successful installation on another Mac.

## Scheduled checks, presentation, and preserved settings

- Enabled automatic checks in the isolated Sparkle domain and observed a real scheduled check. The local server
  received only the `appcast.xml` request, with no DMG download request.
- Settings retained the same window and focus while showing an update-available indicator. The scheduled check
  did not open Sparkle's update window or take focus from the user's work.
- Clicking the indicator opened Sparkle's standard Korean dialog; Later ended the update cycle. This confirms
  the dialog on the current Korean-language Mac, not every macOS preferred-language combination.
- Disabling automatic checks persisted after restarting the fixture, while manual checking remained available.
  The test did not wait a full day to observe repeated long-term scheduling.
- Semantic comparison of `tessera.*` settings before and after showed no changes: 2×2+3×2, gap 0, System language
  and theme, existing directional bindings, and customized **Option+Command+Return** for Maximize were preserved.
  The comparison ignores representation differences such as JSON object key order.

## Seal and public verification

- Pre-publication Run `842478435bcb494d89f30d5e791894ce` for Seal Task
  `tessera-auto-update-alpha4-20260920` passed all four required checks: `unit-tests`, `app-bundle`,
  `website-tests`, and `website-syntax`. Acceptance used that Run. Reverification of this later public-validation
  record is handled separately.
- [PR #8](https://github.com/jgoneit/tessera/pull/8) was merged as commit
  `35b0b2ab0ceae591dd0f61314fd202dca5f37eda`.
- The [v0.1.0-alpha.4 prerelease](https://github.com/jgoneit/tessera/releases/tag/v0.1.0-alpha.4) points to verified
  source commit `8cde98d29d35a39ce95e221e31130e06929eec0f`. The public DMG and `SHA256SUMS` were downloaded again,
  confirming the DMG SHA-256 matches the table above.
- GitHub Pages [deployment Run 35489541006](https://github.com/jgoneit/tessera/actions/runs/35489541006) succeeded.
  The public HTTPS [appcast.xml](https://jgoneit.github.io/tessera/appcast.xml) was downloaded and its signature
  verified using the bundle's public key.
- Browser checks of the [Korean](https://jgoneit.github.io/tessera/?lang=ko) and
  [English](https://jgoneit.github.io/tessera/?lang=en) pages confirmed that download links target the alpha.4 DMG.
  Releases and assets for alpha.1 through alpha.3 were preserved.

## Local installation from the public DMG

- Backed up the existing app to `~/Library/Application Support/Tessera/Backups/Tessera-before-alpha4-20260920.app`
  and separately preserved the original being replaced. Installed the app from the public DMG at `/Applications/Tessera.app`.
- The installed executable matches the final SHA-256 above:
  `3499da2c3f96e3159cb6ae40d44f5e267a8164add0235e42550d1cdf049125c7`.
  A real manual update check in this installation reported `0.1.0-alpha.4` as up to date. Automatic checking is enabled.
- Removed the previous Tessera Accessibility entry and re-added the exact installed path. No macOS authentication
  prompt appeared in this run; the app itself reported ready to arrange windows.
- Confirmed all five shortcuts registered in the installed process (PID `70783`). The custom **Option+Command+Return**
  Maximize binding and all semantic `tessera.*` settings were unchanged, with no user `SUFeedURL` override.
- Stopped local test servers on ports `8769`–`8772` and removed isolated trial Sparkle domains after exporting backups.
  Ordinary user settings were preserved.

## Remaining runtime check

The remaining runtime check for this change is the user's physical-shortcut window placement in the final installation.
Accessibility-ready status and registered shortcuts alone are not recorded as proof of actual window movement.

alpha.3 and earlier have no updater and require one manual alpha.4 installation. An ad hoc signature change may
require renewed Accessibility approval. Multi-display, mixed-scale, other-Mac, macOS 14 runtime, and the existing
unverified requirements for overall v0.1 remain incomplete.
