# Tessera automatic update validation — alpha.4

[한국어](updater-validation.md) | English

Recorded on 2026-09-20 for `0.1.0-alpha.4` / build `4`, using Sparkle `2.10.0`.
Automated checks, offscreen rendering, and real local update installation are distinguished below. At this
recording point, release/Pages publication, final installed-app checks, and Seal completion remain pending.
This is not a claim that overall v0.1 is complete.

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
Successful installation into the test copy does not establish final `/Applications` installation, Accessibility
approval, or successful installation on another Mac.

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

## Pending publication and installation checks

The following are **pending** at this recording point; actual results will be added separately:

- Final `verify` and `complete` with the exact returned Run ID for Seal Task `tessera-auto-update-alpha4-20260920`.
- Purpose-specific commits, push, PR checks and merge, alpha.4 release publication, and public DMG/checksum re-download verification.
- Public HTTPS `appcast.xml` signature, Korean/English download links, and an up-to-date check in the final installed app.
- Backup and replacement of `/Applications/Tessera.app`, Accessibility approval, registration of all five shortcuts, and actual window placement.
- Settings preservation after final installation and cleanup of local test processes, feeds, and updater preferences.

alpha.3 and earlier have no updater and require one manual alpha.4 installation. An ad hoc signature change may
require renewed Accessibility approval. Multi-display, mixed-scale, other-Mac, macOS 14 runtime, and the existing
unverified requirements for overall v0.1 remain incomplete.
