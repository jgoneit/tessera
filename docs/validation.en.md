# Tessera v0.1 validation record

[한국어](validation.md) | English

Status: implementation and validation are ongoing. Overall v0.1 is not considered complete until all items below have been verified.
The user's “잘된다” (“it works”) confirmation records basic behavior in the earlier icon and vertical-navigation version.
For the earlier four-direction global-shortcut version, the user confirmed basic movement with “이제 이동함” (“it moves now”) after that bundle's Accessibility registration was refreshed.
The earlier multi-grid version passed 131 tests, release bundle validation, and Seal Acceptance. Runtime logs confirmed
2×2+3×2 candidate requests and some successful placements, but constraints were repeatedly reported when widening to 2×2 at the right edge.
The subsequent edge-resize fix makes room before resizing. That fix passed 158 automated tests and release bundle
generation/signature checks. After re-registering the new bundle in Accessibility, widening a ChatGPT window from the right third to the right half
was confirmed through actual frame logs and the user's “이제 오른쪽 절반으로 넓어짐” (“it now widens to the right half”) response.
The settings, selector, and result UI support Korean and English, with System, Light, and Dark themes.
The menu bar displays one monochrome template icon. The UI refinement recorded here compresses the settings header, permission status, and spacing,
and adds a subtle keycap background shadow and responsive selector instructions.
A subsequent local-installation change removes the header tagline, installs the app in Applications, and packages an ad hoc DMG.
Success in an earlier version is not treated as proof that this bundle or every multi-grid combination has passed.

## Environment

- macOS 26.6.2, Apple Silicon
- Swift 6.4, Command Line Tools
- Initially detected display: one TFG40U12PW, 5120×2160pt, scale 1, visible frame `(0, 0, 5120, 2130)`
- Configured minimum deployment target: macOS 14. Runtime behavior on macOS 14 has not been separately verified.

## Local installation and DMG — 2026-09-19

- Removed the tagline below the logo and app name in settings, along with its unused Korean/English translation entries.
  The new build's accessibility tree confirmed that the header contained only Tessera and the version.
- `TESSERA_UI_PREVIEW_DIR="$PWD/.build/install-previews" swift test`: 174 tests passed (Core 57, App 117).
  Checked the layout after removing the tagline in a representative Korean minimum-size settings render.
  `bash scripts/build-app.sh`: release app, translation resources, icons, Info.plist, and ad hoc signature checks passed.
- Preserved the previous development app at `.build/tessera-before-install.qbcvqc_x/Tessera.app`.
  Copied the app to `/Applications/Tessera.app` and verified its signature; the source and installed executables had matching SHA-256 hashes.
  Stopped the process running from the development path, then confirmed a process running from the installation path.
- After the user completed macOS authentication, updated the existing Tessera Accessibility entry to `/Applications/Tessera.app`.
  Confirmed the enabled state in System Settings and the app's ‘창을 배치할 준비가 되었어요’ (“Ready to arrange windows”) status.
  Grid, gap, language, theme, and all four direction bindings were unchanged after replacement (shortcut JSON compared by object content).
- `bash scripts/build-dmg.sh --skip-build`: generated `dist/Tessera-0.1.0-arm64.dmg` and passed `hdiutil verify`.
  Size: 2,158,858 bytes. SHA-256: `709094ade6dc9ce83f1c38382a33fdc966f0e7e5c7b893bfa7f0d4e468c1f1a8`.
  Mounted read-only, checked the app signature, file equality with the installed app, Applications link, and bilingual installation guide, then ejected it.
- At this stage, the DMG was a local ad hoc Apple Silicon build. Developer ID signing, Apple notarization, and web upload had not been performed.
  Gatekeeper behavior after an internet download, installation on another Mac, and actual Intel/macOS 14 execution remained unverified.
  Full window-placement validation of this installed copy and the existing multi-display checks also remained incomplete.
- Preserved the existing Seal Tasks and Runs; they are not reused as Acceptance for this follow-up change.
  Automatic Seal activation was skipped for this request because the worktree contained an untracked user prototype.

## Automated validation

| Item | Result |
| --- | --- |
| Foundation bundle metadata tests | Passed |
| Foundation release .app generation and ad hoc signature verification | Passed |
| Icon and vertical-navigation version tests | 68 passed (Core 38, App 30; includes some parameterized cases) |
| Earlier four-direction global-shortcut integration tests | `swift test`: 107 passed (Core 38, App 69; includes some parameterized cases) |
| Earlier four-direction global-shortcut release bundle | `bash scripts/build-app.sh` passed. ICNS generation, Info.plist checks, ad hoc signing, and signature verification passed |
| Earlier multi-grid integration tests | `swift test`: 131 passed (Core 48, App 83; includes some parameterized cases). Includes all 7 selection combinations and 2×2 Geometry |
| Earlier multi-grid release bundle | `bash scripts/build-app.sh` passed. ICNS, Info.plist, and ad hoc signature verification passed |
| Earlier multi-grid Seal | `TESSERA-V01-MULTIGRID-20260917`, Run `7319c7d0498745209bacc9a9d9826944` accepted |
| Edge-resize fix tests | `swift test`: 158 passed (Core 57, App 101; includes some parameterized cases). Covers width/height expansion at boundaries, stopping writes after cancellation/failure, read failures, and partial-change handling |
| Edge-resize fix bundle | `bash scripts/build-app.sh` passed. ICNS, Info.plist, and ad hoc signature verification passed |
| Earlier edge-resize Seal | `TESSERA-V01-EDGE-RESIZE-20260918`, Run `b64e6869e09b47d88410d9dd31ff4d3e` accepted |
| Previous Seal Tasks and Runs | Preserved `TESSERA-V01-20260917`, `TESSERA-V01-ARROWS-20260917`, `TESSERA-V01-ICON-NAV-20260917`, `TESSERA-V01-DIRECTIONAL-20260917`, `TESSERA-V01-MULTIGRID-20260917`, and existing Runs |
| Seal for the earlier UI change | Automatic activation skipped because this was a new request without explicit selection and the existing worktree was dirty. Existing Tasks and Runs preserved. Tests and bundle checks run directly |
| UI, language, and theme automated checks | `TESSERA_UI_PREVIEW_DIR="$PWD/.build/ui-previews" swift test`: 174 passed (Core 57, App 117; includes 2 offscreen render tests). Validated 179 translation keys each for en/ko |
| UI release bundle | `bash scripts/build-app.sh` passed. en/ko translation resources included and syntax-checked; ICNS, Info.plist, and ad hoc signature verification passed |

## Settings and selector UI refinement

- Kept the default 680×800pt and minimum 640×620pt settings sizes and scrolling. Set outer padding to 24pt, section spacing to 16pt,
  the header icon to 48pt, and the name to 22pt. Granted permission uses a small status row; missing permission uses an explanatory card.
  Both states retain Open Settings and Check Again buttons and their accessibility names.
- Display and shortcut cards have 16pt inner padding; the grid card retains 20pt. Shortcut collapsing, expansion on error,
  recording, applying, and saving are unchanged. Only the keycap background gains a subtle shadow offset downward by 1pt;
  Increase Contrast removes the shadow and strengthens the border.
- The selector removes the duplicate height badge while retaining the current placement text and a 28pt two-line status area.
  Four instruction groups occupy one or two lines depending on width. The number range changes to 1–4/6/8 for the displayed grid.
  Added both en/ko wording. Core, AX, key handling, storage formats, and the menu icon were unchanged.
- The user's `docs/design_prototype.html` is preserved as the local original and excluded from version control and the PR.
  SHA-256: `d50e0cfc1acacb515e2bb41633e22529ca2c72cb2ec4ce26aa2ea4726493b26b`.
- `TESSERA_UI_PREVIEW_DIR="$PWD/.build/ui-polish-previews" swift test`: 174 passed (Core 57, App 117).
  Generated 52 PNGs covering default/minimum/full-height settings, all three grids, long app/display names and constraint messages, and wide/narrow selectors.
  Representative Korean/English and light/dark images showed no overlap in settings controls, full-column outlines, or one-/two-line instructions.
  At minimum height, lower settings remained in the scroll area; the full-height render at the same width was also checked.
- Also generated images with high-contrast NSAppearance. This does not establish that the real OS accessibility settings propagate through the SwiftUI environment.
  These render checks do not activate the app, register shortcuts, or change user settings.
- New Basic Task `TESSERA-UI-POLISH-20260918` uses risk=low, verifier.required=false,
  and the existing two required checks with a 300-second timeout each. Previous Tasks and Runs are preserved.
- Seal Run `d22f129812694645a1fa0a1ae91341c6` passed `unit-tests` and `app-bundle`;
  Basic Completion used the exact returned Run ID. The runtime results below were recorded after verification.
  App code was not changed and the bundle was not rebuilt during those UI-polish runtime checks.
- Preserved the previous app at `.build/tessera-before-ui-polish.EHperw/Tessera.app`.
- Ran the verified `dist/Tessera.app` and re-registered the existing Tessera Accessibility entry for that bundle.
  Confirmed permission in System Settings, the running app's ‘창을 배치할 준비가 되었어요’ (“Ready to arrange windows”) row,
  Open Settings and Check Again buttons, and the default collapsed state for successfully registered shortcuts.
- Checked the grid, gap, and display controls in the real settings window at default 680×800pt and minimum 640×620pt sizes.
  At minimum size, expanded shortcuts and scrolled down to access all four recorders, the explanation, and the Apply button.
  Restored the default size, top scroll position, and collapsed shortcuts afterward.
- Checked the running app's Light and Dark settings with macOS Increase Contrast enabled and Reduce Transparency enabled alongside it.
  Card, control, and common-keycap borders and text remained distinguishable. Restored both OS settings to their previous off values
  and the app theme to System afterward. This is not a complete direct validation of the real selector's high-contrast appearance.
- Compared UserDefaults before and after replacement: 2×2+3×2, gap 0, system language/theme, and all four direction shortcuts were preserved.
  Shortcut comparisons ignored JSON key order and compared content.
- Physical global-key input, selector focus, all real window constraints, and multiple displays remain separately incomplete for this presentation change.
  The earlier bundle's user-confirmed placement is distinct from this UI/permission/settings-preservation check; overall v0.1 is not marked complete.

## Larger direction-shortcut disclosure area

- Replaced the small default disclosure arrow with an arrow on a 24pt background and a full-row button with
  a minimum 44pt content height and 16pt padding. The collapsed card is 76pt high; title, status, empty space, and padding share the same button area.
- `DisclosureGroupStyle` uses the existing `isExpanded` Binding, retaining recording cancellation when collapsed,
  expansion on error, and draft preservation. Expanded content is a separate area with Korean/English accessibility expansion states.
- `TESSERA_UI_PREVIEW_DIR="$PWD/.build/disclosure-previews" swift test`: 174 passed.
  Existing render checks verified the expanded header, all four direction inputs, and Apply button in a narrow settings view.
- Basic Task `TESSERA-UI-DISCLOSURE-20260918` covers the earlier UI change and this follow-up.
  It retains risk=low, verifier.required=false, and 300-second timeouts for both `unit-tests` and `app-bundle`.
  Previous Tasks, Runs, and the user's design prototype are preserved.
- Preserved the previous bundle at `.build/tessera-before-disclosure.nohu4650/Tessera.app`.
- Seal Run `abed48a491b741848bd1f024524c6f3b` passed both required checks, and complete used that exact Run ID.
  The runtime notes below were added after verification; app code and bundle were unchanged afterward.
- Ran the verified app and refreshed the same Tessera app's existing Accessibility permission, confirming ready status.
  In the running app, clicking empty space in the middle of the header expanded it; clicking the button collapsed it. Checked the accessibility tree's title, status, and expanded value.
  Starting recording, collapsing, and reopening also restored the existing key display and left Apply disabled.
- Grid, gap, language, theme, and all four bindings were preserved across replacement. Shortcut JSON was compared as object content.
  Collapsed shortcuts and restored the top scroll position after verification.
- Could not focus the header through Tab navigation with the current OS configuration, so complete Tab/Space and VoiceOver operation remain unverified.
  User keyboard-navigation settings were unchanged; the implementation uses a native Button. Existing multi-display checks remain incomplete.

## Monochrome menu-bar icon

- Draws the supplied reference's three-region shape as an 18pt AppKit vector image. Opaque shapes on a transparent background
  use `isTemplate = true`, allowing the macOS menu bar to handle coloring.
- The square status item displays only the image. Removed the app-name text while retaining the Tessera accessibility name and localized tooltip.
- The app bundle/settings color icon and window-placement behavior are unchanged.
- Explicitly selected Seal Task `TESSERA-V01-MENU-ICON-20260918` includes the full cumulative product change.
  Previous Tasks and Runs are preserved; the same two required checks have 300-second timeouts each.
- Seal Run `de1587e1b97a4d488344bac9802abf22` passed both required checks; Basic Completion used the exact Run ID.
  These runtime results were recorded after verification, using the verified `dist/Tessera.app` without code changes.
- Preserved the previous bundle at `.build/tessera-before-menu-icon.yri4lx/Tessera.app`.
  Confirmed preservation of 2×2+3×2, gap 0, system language/theme, and shortcut registration in the new app.
- Re-registered the existing Tessera Accessibility entry for the new ad hoc build. After the user completed macOS authentication,
  confirmed the on indicator in System Settings and ‘다시 확인’ (“Check Again”) → ‘창을 배치할 준비가 되었어요’ (“Ready to arrange windows”) in the running app.
- The UI tool captured only the app's settings window; the SystemUIServer connection timed out, so the menu bar itself
  was not visually inspected. Menu-bar light/dark appearance, selected state, and VoiceOver remain unverified.

## UI, language, and theme validation

- Select grids through preview cards and adjust gap, theme, and language in the same settings window.
  Successfully registered shortcut customization starts collapsed; errors or missing registration expand it. Collapsing cancels recording while preserving the draft.
- Language options are System, 한국어, and English; theme options are System, Light, and Dark. They apply immediately and persist across restarts.
  Corrupt values fall back to System. Switching preserves existing grid, gap, and four-direction bindings.
- Menus, selector, result/error messages, recorder, and accessibility names are localized. The macOS 14 deployment target is unchanged.
- Automated checks cover English/Korean key and format-placeholder parity, missing literal translation-call keys,
  preferred-language selection, saving, restoration, recovery from corrupt values, and recording cancellation.
- `PresentationRenderTests` generates PNGs using separate UserDefaults and non-displayed NSWindow/NSHostingView instances.
  It does not activate the app, register shortcuts, or change user windows/settings.
  This is distinct from checking focus, clicks, and system-theme changes on a real screen.
- The first integration check found locale-specific thousands separators appearing in error codes; corrected this to preserve the original code value.
  Updated an existing test that expected the English Space label to expect the key name in the current language.

All 174 automated checks passed, generating 20 PNGs in `.build/ui-previews/`.
Directly inspected representative Korean/English settings in light/dark, 2×2 single-zone and 3×2 full-column selectors,
and long constraint notices for text overlap, clipping, and selection highlighting. Changed inner full-column borders to
a neutral color so the continuous outline is more clearly distinguished from a single-zone selection.

On 2026-09-18, directly checked the following in the new release app on the current Mac:

- Actual rendering and readability in the Korean System-theme view, after switching to Light and English, and in English Dark mode.
- Saved language as English and theme as Dark, terminated and relaunched the app process, and confirmed those values and the English window title persisted.
- Restored both language and theme to System and confirmed Korean text. Did not change the OS theme itself.
- Unchecked 2×2 in the new grid cards and confirmed the last remaining 3×2 item became disabled, then restored 2×2+3×2.
  Gap 0 and the four directional shortcuts were preserved. Checked shortcut customization expansion/collapse and English recording instructions.
- Re-registered only the previous Tessera entry in System Settings for the current `dist/Tessera.app`. After the on indicator appeared,
  pressing Tessera's ‘다시 확인’ (“Check Again”) changed its status to ‘창을 배치할 준비가 되었어요’ (“Ready to arrange windows”).
- Preserved the previous bundle at `.build/tessera-before-ui.e6GiHv/Tessera.app`.

Tessera's own UI connection worked during this validation. Tool-connection failures in earlier versions remain preserved as historical records.
Physical global keys, selector focus, every actual constraint message, automatic OS-theme switching, full VoiceOver operation,
and multiple displays remain separately incomplete for this UI bundle. The user's edge-expansion confirmation concerns the earlier bundle.

## Real macOS validation

| Item | Procedure | Result |
| --- | --- | --- |
| Menu bar and settings | Launch, remain in the menu bar, and display Settings | Confirmed the new settings UI, user icon, two languages, three theme choices, and expansion/collapse of four-direction customization. Direct menu interaction remains pending for the new UI version |
| Multiple-grid selection | Select 2×2/3×2/4×2 in menus and settings, prevent removing the last item, and retain settings after restart | Confirmed preservation and restart of 2×2+3×2 and Gap 0 in the new UI. Confirmed the card blocks deselecting the last 3×2. Real placements across all combinations remain pending |
| Spatial-order navigation | Order by selected grids' column centers, wrap horizontally, preserve height across grids, and retain the grid during vertical movement | Confirmed successful horizontal moves/wraparound and top/full/bottom placement in a ChatGPT window with the fixed bundle, 2×2+3×2, Gap 0. All combinations, repeat, and input-state checks remain pending |
| Right-edge expansion | Move from the right 3×2 column to the right 2×2 column and inspect the actual frame | Confirmed pre-move → width expansion → matching final frame for full-column and bottom-zone placements in the fixed bundle. User confirmed “이제 오른쪽 절반으로 넓어짐” (“it now widens to the right half”) |
| First input and selector transition | First horizontal input from an arbitrary window center, restore matching frames, and match displayed grid to 4/6/8 numbers and clicks | Unverified in the new multi-grid version |
| Cancellation during settings changes | Change selected grids or Gap during input or AX placement and stop further writes | Unverified in the new multi-grid version |
| Permission absent | Request Arrange before permission; check guidance and no crash | Logs in the earlier four-direction version showed receipt of global keys followed by `permission required`, stopping placement and opening settings |
| Permission granted/revoked | Check Again after granting Accessibility, then block placement after revocation | Confirmed System Settings on state and actual placement after re-registering the edge-resize bundle on 2026-09-18. Revocation during placement remains pending |
| Earlier version's basic behavior | Physical key input in the icon/vertical-navigation fix app | User's latest “잘된다” (“it works”) confirmed basic behavior after the earlier “이동 안 함” (“does not move”) report; this does not mean every detailed scenario passed |
| Four-direction direct placement | Arrange with ⌃⌥←/→/↑/↓ without a selector, preserving original app focus and typing | Actual successful placements in all four directions were logged for the fixed bundle's ChatGPT window. Separate focus/typing-preservation validation remains pending |
| Result display | Show exact placement for 1 second and errors/app constraints for 4 seconds | Unverified in the new version |
| Global-key repeat | Hold horizontal keys; release keys/modifiers; one vertical step per press | Unverified in the new version |
| Continuity and AX | Consecutive input on the same window, size constraints, manual movement/resizing, and window switches | Confirmed Zone 2 → Column 2 full height → Zone 5, horizontal wraparound, and continued placement after constraints in the earlier four-direction version. Some transitions passed in the earlier multi-grid version. This fix combined with manual frame changes/window switches remains pending |
| Menu selector | Open only through Arrange Window…; use ordinary/global direction keys and Enter/Esc | New path unverified |
| Clicks and numbers | Place the original window in each 2×2/3×2/4×2 Zone and close the selector | All Zone combinations in the new version remain pending, separate from earlier user confirmation of basic operation |
| Input and cancellation | Korean input, number pad, outside clicks/switching, and no number-key leakage from the selector | Detailed combinations pending |
| Four-direction settings | Record four drafts; Apply together; swap keys; duplicates; conflicts with system/other apps; restart | New version unverified. Distinct from earlier confirmation of single-key saving and restart persistence |
| Registered keys during recording | Preserve existing registration, press a registered key, and change only the draft | New version unverified |
| Stored-value migration | Migrate the old single key to four defaults while preserving Layout/Gap | Automated tests passed; actual upgrade/restart confirmation pending |
| App constraints | Terminal size increments, apps with large minimum sizes, fixed-size windows/modals | Pending |
| Target lost | Safe results when a window closes, app switches, or full screen is active | Pending |
| Built-in and external displays | Place on each display | Waiting for environment preparation |
| Relative origins and scales | External display left/right/above/below with different scales | Waiting for environment preparation |
| Dock and menu bar | Check visible frame with Dock left/right/bottom and auto-hide | Pending |
| Display connection changes | Disconnect an external display during selector/direct placement and cancel placement | Waiting for environment preparation |

Manual checks use temporary windows in a general editor or Finder. They do not modify the contents of the user's active work windows.
Items requiring OS permission or physical display connections resume after the user prepares the environment.

After launching the earlier four-direction global-shortcut release app, the UI control tool initially failed with
`Sky Computer Use native pipe closed before response`, preventing permission refresh. A later run restored the System Settings connection;
removed only the existing Tessera entry and re-added `/Users/jgoneit/project/tessera/dist/Tessera.app`. Confirmed the on indicator,
then observed placement requests and `Window arranged.` final-frame confirmations in the actual process logs. The user
confirmed direct movement with “이제 이동함” (“it moves now”). The UI tool still failed to read Tessera's own settings window,
so this does not count as successful real-app settings validation.

On 2026-09-18, logs confirmed launch of the multi-grid release process and registration of all four Carbon shortcuts. Re-registered that bundle
at the same dist path in Accessibility and confirmed the on indicator in System Settings. Tessera's own UI connection still failed,
so asked the user to select 2×2+3×2 in Settings and check actual spatial-order navigation. Preserved the earlier working version at
`.build/tessera-before-multigrid.Qeb7dy/Tessera.app`.

The user subsequently reported “2×2 오른쪽이 안됨” (“the right side of 2×2 does not work”). Runtime logs confirmed `twoByTwo` and `threeByTwo`
were selected with Gap 0. Widening from the right 3×2 column to the right 2×2 column frequently produced constraint results,
while requests from the middle 3×2 column to the same right 2×2 column and placements in the left 2×2 column succeeded.
There is evidence of candidate selection and some real movement, but not successful placement at the right edge at that stage.
The fix targets the path where resizing at the current origin first crosses the screen boundary;
results must be checked again after the fix, separately from actual app size constraints.

In an initial check, the automation tool's global-key input reached TextEdit as a control character and was immediately undone.
That input is therefore not used as evidence of successful real Carbon global-shortcut delivery.
User physical-key input is checked alongside app logs; user confirmation for an earlier version is not extended to new multi-grid behavior.

## Screen-edge resize fix

The Task for this fix is `TESSERA-V01-EDGE-RESIZE-20260918`. Existing multi-grid navigation and the serial queue are retained;
the AX placement sequence gains an optional preparatory move to make room for resizing.

1. From the initial and requested frames, determine whether the requested size at the current origin would exceed the screen's visible frame.
2. If space is insufficient, take the maximum of the current and requested width and height. Clamp the
   **current origin** inside the screen using that footprint, then move once. The final position is determined after reading the size.
3. Apply the requested size once, then read the actual size.
4. Clamp the requested position inside the screen using the actual size, move once, then read the final frame.
5. Compare requested and actual frames to classify the result as applied or app-constrained. A minimum size larger than the screen remains a constraint.

Including the preparatory move, at most three position/size writes occur, with no retries. Each write is preceded by
the existing target/cancellation validity checks. Failure after any attempted write reports the possibility of partial changes and stops.
A failed AX write is not assumed to be free of side effects; there is no automatic rollback.

Local logs include the PID and `requested`, `initial`, `prepared`, `resized`, and `final` frames to distinguish room preparation
from the response after resizing. Window titles and document contents are not logged.

Automated tests reproduced the previous right-expansion failure with a fake window that limits size to the space remaining at its current origin.
The revised sequence applies the requested frame for right full-column, top-zone, and bottom-zone placements. Center/left paths with
enough space skip the preparatory move; actual minimum-size limits are reported as constraints without retrying.
Injected permission/target changes and Task cancellation at each write boundary to check that later writes stop and partial-change notices appear.
These are automated fake-window checks; real-app results are recorded separately below.

Launched the fixed bundle at 2026-09-18 00:27 and confirmed all four Carbon shortcut registrations in logs.
Removed only the existing Tessera Accessibility entry, re-registered the same `dist/Tessera.app` path, and confirmed the on indicator.
The existing tool error still affected Tessera's own UI connection, so asked the user to retest the affected window with physical keys.
Preserved the previous bundle at `.build/tessera-before-edge-resize.CWFCbj/Tessera.app`.

At 2026-09-18 00:28:50, confirmed the right full-column transition with Gap 0 in a ChatGPT window. In AX coordinates,
the initial `(3414, 30, 1706, 2130)` became `(2560, 30, 1706, 2130)` after the preparatory move,
then matched the requested `(2560, 30, 2560, 2130)` in both size and final position. The right bottom zone also applied as
`(3414, 1095, 1706, 1065)` → preparatory move → `(2560, 1095, 2560, 1065)`.
The user confirmed “이제 오른쪽 절반으로 넓어짐” (“it now widens to the right half”). Moving from the middle column to the right half
applied exactly without a preparatory move. Logs also confirmed left-side expansion/shrinking, horizontal wraparound, and expansion from bottom to full column.
This evidence is limited to that app, display, and Gap 0; it does not establish that Korean input, long presses, or every app constraint passed.
Saved local reproduction logs in `.build/tessera-edge-resize-native.log`.

Manual verification scope and outstanding items:

- With 2×2+3×2 and Gap 0, move from the right 3×2 column to the right 2×2 column. Check that the requested grid and final width/position
  match, along with preparatory-move and post-resize frame logs. Full-column and bottom-zone cases are confirmed above;
  the equivalent right-top edge-expansion path still awaits manual testing.
- Also check the comparison paths: middle 3×2 column → right 2×2 column, and left 3×2 column → left 2×2 column.
  Confirm that no unnecessary preparatory move occurs where enough space already exists.
- Check the same paths with Gap 8, as well as returning from the wider 2×2 to the narrower 3×2.
- For windows with a minimum-size constraint, distinguish constraint messages from exact placements. Record automatic test results and actual observations
  separately for whether cancellation/failure stops subsequent writes.

Gap 8, top-zone edge expansion, app minimum-size constraints, and actual cancellation/failure injection remain pending for manual testing.
Multi-display negative origins and mixed scales remain on the existing pending list.

## Multi-grid implementation and validation scope

- Available grids are 2×2, 3×2, and 4×2, with at least one selected. The default is 3×2 alone.
  Menus and settings share the same selection list; Settings prevents unchecking the last remaining checkbox.
- Horizontal candidates combine selected grids' column centers in screen-position order. For example, 2×2+3×2 uses
  `3×2 column 1 → 2×2 column 1 → 3×2 column 2 → 2×2 column 2 → 3×2 column 3`.
  Vertical input retains the grid/column and changes only top/full/bottom; horizontal input preserves that height state.
- If the current frame matches an active candidate's top/full/bottom frame, restore that selection. Otherwise,
  the selector highlights the full column nearest the original window center, breaking ties to the left. First horizontal input
  chooses the nearest candidate in the pressed direction from the original window center. Opening the selector alone does not place the window.
- The selector displays the current candidate's grid. Number keys and the number pad select only 1–4/1–6/1–8 for that grid;
  out-of-range numbers are consumed without placement. Clicks pass both the displayed grid and Zone.
- `tessera.enabledLayouts.v1` stores a raw-value array in 2×2, 3×2, 4×2 order. Valid duplicates are normalized;
  an empty array, invalid type, or array containing unknown entries resets the entire selection to 3×2 alone.
  The old `tessera.defaultLayout` migrates to a single selection only when the new key is absent; saving the new list removes the old key.
  The Gap and four-direction shortcut storage contracts are unchanged.
- Cancellation on settings changes runs through the Coordinator's synchronous observation of shared settings.
  It does not rely on a delayed Settings-only onChange; menu changes use the same path.

Settings tests cover all seven selection combinations, preventing removal of the last item, duplicate normalization, new-key precedence,
migration from the old single value, and recovery from corrupt stored values. See the 131-test result and Seal record above
for the multi-grid version's automated checks. The earlier right-expansion failure and later edge-fix success are distinguished in the runtime notes above.

## Four-direction global-shortcut implementation

- Defaults are Control+Option with left/right/up/down arrow keys. Direct placement preserves the original app's focus
  and does not open a selector. Success notices are implemented for 1 second; error/app-constraint notices for 4 seconds.
- Arrange Window… in the menu is a separate selector path, operated through ordinary arrow keys, numbers, and clicks.
  Registered directional combinations use a distinct path so an open selector does not process them twice.
- Horizontal repeat uses registered-key press/release events and an internal timer. Vertical input advances one step per new press.
  After input cancellation, recording, or registration changes, leftover events and repeat state cannot start new placements.
- Edit four shortcut drafts and Apply them together. If a candidate registration fails, remove the added registrations and preserve the existing four keys
  and stored values. Existing keys stay registered during recording; Carbon callbacks feed the active recorder's draft.
- `tessera.directionalShortcuts.v2` stores all four valid bindings together. The old single key migrates to the four defaults
  while preserving Layout/Gap. Corrupt, missing, or duplicate values reset the entire group to defaults.
- Logical position during consecutive input is separate from the actual frame read through AX. An app-constrained size does not discard
  the accepted vertical step; target, screen, settings, or manual frame changes restart navigation from the current state.
- Input received while AX prepares is applied in order; actual writes are serialized. After an in-flight request, apply only the last
  pending request. Target loss, failure, or forced cancellation stops further writes.

Shortcut registration, rollback on failure, event order, and repeat cancellation are tested with fake registration backends and clocks.
Automated tests also cover settings migration, persistence of all four values, a single active recorder, registered-key draft delivery, and physical-key handling with Korean input.
Placement tests with a delayed executor verify a maximum concurrency of 1, handling of the last pending request, and cleanup on normal exit/cancellation/failure.
These results are separate from evidence of real Carbon delivery, AX responses, or macOS focus preservation.

The final frame is classified as exact only when all four edges match the requested frame within `0.001pt`.
Existing regression tests cover fractional coordinates, floating-point noise, subpixel differences on 2× displays, and accumulated boundary errors.

## Earlier icon and vertical-navigation fix record

- Preserved the supplied PNG original and used it for the app bundle, menu bar, and settings icon in that version.
  Generated standard 1×/2× representations from 16–1024px using `sips` and `iconutil`.
- Changed reopening to continue from the matching top/bottom Zone when the actual frame matches the current layout/gap/scale.
  Applied a one-step-per-press limit where vertical auto-repeat had skipped the full-column stage.
- That version passed 68 `swift test` tests and release bundle/ad hoc signature verification.
  Directly inspected the settings icon, re-registered the bundle after user authentication, and confirmed Accessibility was enabled in the app.
- The fixed version initially received an “이동 안 함” (“does not move”) report and logged selector display followed by cancellation. The user's later
  “잘된다” (“it works”) updated the record to confirm that earlier version's basic behavior. See above for the subsequent four-direction global-shortcut confirmation;
  detailed cancellation, multiple displays, and new multi-grid runtime checks remain separate.
- The Task for that change is `TESSERA-V01-ICON-NAV-20260917`, preserved alongside previous Tasks and Runs.

## Size-adjustment feedback for top/bottom placement — 2026-09-19

AX logs from the running ChatGPT window showed a requested top/bottom cell height of `474.5pt`
being adjusted to `600pt`. The top cell aligned at `y=33`, and the bottom cell at `y=382`, inside
usable screen bounds with a bottom edge of `982pt`. The previous four-second notice combined
this size adjustment with position problems, making correctly aligned placement sound like a failure.

- Kept `.constrained` and added reasons for size adjustment, position mismatch, and overflow beyond
  the usable display area. Contained final readback matching the clamped origin calculated from its
  actual size is classified as size-adjusted. Overflow takes precedence; AX errors and partial-write handling remain unchanged.
- Exact success and “Arranged · Adjusted to app size” appear for one second. Position mismatch,
  overflow, errors, and unclassified constraints appear for four seconds. The picker and recent result use the same copy.
- Strict four-edge `0.001pt` comparison, manual-movement detection, AX write order/count/timeout,
  and logical navigation state are unchanged.
- All 37 focused placement, result, and localization tests passed. Coverage includes the observed
  2×2/3×2 top/bottom adjustment, a second size adjustment during the final move, ignored position
  writes, overflow precedence, and the one-/four-second feedback policy.
- One offscreen picker/feedback render test passed and produced 40 images. The Korean dark and
  English light size-adjustment notices were visually checked for unclipped text and borders.
  This is separate from installed-app validation.
- This change does not replace the public DMG. Existing multi-display and mixed-scale native checks remain pending.

Seal Task `tessera-placement-feedback-20260919`, Run `ea2121c555944073b14fefa08e1fbc65`,
received accepted Basic Completion after the required `unit-tests` and `app-bundle` checks.
The verified bundle was copied to `/Applications/Tessera.app` and its signature was checked.
Both built and installed executables had SHA-256
`e739a5914dc4d464304f2c174e3b474b6238eb879b772f700e9a39ab755f306a`.
Saved grids, gap, four direction bindings, language, and theme matched before and after installation.
The previous app is preserved at
`~/Library/Application Support/Tessera/Backups/Tessera-before-placement-feedback-20260919.app`.
After the user completed macOS authentication, `/Applications/Tessera.app` was registered again in
Accessibility settings. The installed app reported ready after “Check Again.” Settings remained semantically
identical after relaunch and permission refresh (ignoring object-key order in the shortcut JSON).

Installed-app checks are complete for this fix. The user confirmed normal top/full/bottom movement
and a brief notice in ChatGPT, and separately confirmed normal behavior in TextEdit.
AX logs for the verified TextEdit process also showed an exact full-height placement at
`(0, 33, 756, 949)` classified as success, and a top-cell height adjustment from `474.5` to `475pt`
classified as “Arranged · Adjusted to app size.” Notice duration was validated through the user's
visual confirmation and automated one-/four-second policy tests; the logs do not measure display duration.
Existing multi-display and mixed-scale native checks remain separately incomplete.

## Maximize, screen halves, and Settings window visibility — 2026-09-19

This change extends the local work above, including the size-adjustment feedback fix, with maximization,
screen halves, and regular-app visibility while Settings exists. It does not replace the public DMG or website.

- Maximize fills the latest `visibleFrame` with no Gap and remains maximized when repeated. Its default shortcut is
  `⌃⌥Return`; the menu and picker button use the same action. macOS's separate full-screen Space remains unsupported.
- Up/down traverses the full-width `top half ↔ maximized ↔ bottom half` states and stops at either end.
  Screen halves use the configured Gap and existing pixel alignment; only maximization omits Gap.
- Left/right from a screen-wide state enters the nearest active grid column in that direction from the screen center,
  preserving height. With 2×2+3×2, maximize→left enters the full left 2×2 column. With all three grids,
  the closer 4×2 columns 2 and 3 are used. Maximization is not inserted into the grid's horizontal cycle.
- Maximize and direction input received during initial capture is applied in order. Latest-pending coalescing, serial AX
  execution, cancellation checks before subsequent writes, and the 0.5-second timeout remain. Maximize is one-shot and stops horizontal repeat.
- The picker remains open after maximizing and outlines the whole preview or a top/bottom row as one connected shape.
  Screen-wide labels omit the grid name. Number/click selection in the displayed grid and Enter/Esc closing remain available.
- Existing four-direction custom bindings migrate to `tessera.placementShortcuts.v3`, adding an optional maximize binding.
  A maximize conflict during initial migration leaves only maximize unassigned and preserves direction bindings.
  Later apply failures retain the existing active set. Recording blocks placement while retaining registrations and active-draft delivery.
- Before opening Settings, Tessera changes to regular-app mode. Dock/⌘Tab visibility stays while Settings is minimized
  or behind another app; closing it restores menu-bar-only mode. The picker and feedback alone do not create a Dock icon.
  Mission Control window/icon presentation requires separate native verification.

The initial integrated run passed 66 Core and 146 App tests, including maximize/screen-half navigation and
geometry. After adding interrupted-migration recovery, 59 focused settings and shortcut tests passed.
The picker Maximize button now stops held global and plain horizontal repeat; regression tests also check
the separate registered-Maximize and ordinary Return/Escape event paths.

Two offscreen render tests passed for Korean/English and light/dark appearances. The narrow English top-half
picker and Korean maximized picker were visually checked for outlines, controls, and guidance. A long shortcut
keycap overlapping the settings guidance was corrected, settings rendering passed again, and the Korean dark
render confirmed that the overlap was removed.

Final Seal and installed-app results are recorded below. Existing multi-display and mixed-scale runtime checks
remain separately incomplete.

Seal Task `tessera-maximize-mission-control-20260919`, Run
`133af0355dc347eabb3e6738ea31e985`, executed the required `unit-tests` and `app-bundle` checks.
Basic Completion was accepted using that exact Run ID. Another 31 focused input, picker, and placement-queue
tests passed. The offscreen render checks generated 84 images.

The previous installation was preserved at
`~/Library/Application Support/Tessera/Backups/Tessera-before-maximize-20260919.app` before installing
the verified bundle at `/Applications/Tessera.app`. Its signature was verified, and the build and installed
executables both have SHA-256
`58baf90bfeb01550eb95de30d410efacf9ba40f8a7164374bbea25ca548a2eb1`.
The enabled 2×2+3×2 grids, Gap 0, system language/theme, and all four direction bindings remained unchanged.
Maximize registered as `⌃⌥Return`; the v2 key migrated to v3 and its pending-migration marker was cleared.
After the user completed macOS authentication, the installed path was re-registered in Accessibility.
Tessera's permission recheck then showed that it was ready to arrange windows.

The running process reported regular activation policy while Settings was open. This metadata alone is not
proof of the actual Mission Control window/icon presentation. The user confirmed normal physical-key behavior
for maximize→left 2×2 column and top half→maximize→bottom half. They also confirmed the Mission Control
window/icon and Dock/⌘Tab presentation, including Settings minimization, reopening, and closing.

AX logs from the same installed build showed an exact maximized requested/final frame of
`(0, 33, 1512, 949)`. The app adjusted requested top/bottom half heights from `474.5` to `475pt`,
aligned them at `y=33` and `y=507`, and classified both as “Arranged · Adjusted to app size.”
Logs also confirmed physical hotkeys and placements for maximize→right 2×2 column and
bottom half→bottom-right 2×2 cell. A final read-only code review found no additional defects.
Multi-display and mixed-scale native checks remain incomplete. Public DMG/website updates,
commits, and pushes were not part of this task.

## Maximize web demo and alpha.2 publication — 2026-09-19

This release includes the native changes above and the matching web maximize demo in `v0.1.0-alpha.2`.
Existing Tasks/Runs and alpha.1 are preserved. The app is version `0.1.0`, build `2`, ad hoc signed for
Apple Silicon. The currently installed app is not replaced.

- All 49 web tests and `node --check website/app.mjs` passed, covering seven grid combinations,
  screen-wide placement/height/grid entry, Gap/pixel alignment, bilingual messages, and asset hashes.
- Local browser checks confirmed maximize→left 2×2 column, top half→maximize→bottom half, and entry
  into the right central 4×2 column when all grids are selected. Screen-wide placement survived grid,
  language, and theme changes.
- Maximize's Enter/Space activation, numeric/click selection, and non-interception of modifier combinations
  were checked. Korean/English, light/dark, and 390px layouts were inspected; at 320px the controls wrapped
  without horizontal overflow.
- Browser inspection caught height-label updates overwriting the note preview. Scoping the selector to
  the guidance fixed it; note preservation, maximization, and numeric selection were rechecked.
- Physical Korean IME input and other browser engines were not separately tested in this web change.
  Existing native multi-display/mixed-scale verification remains incomplete.

Seal, DMG, and public-URL verification results are recorded below after completion.

Seal Task `tessera-maximize-web-alpha2-20260919`, Run `4ba27a9478e54f3cb0bb97b7b4dc36ed`, passed
required `unit-tests`, `app-bundle`, `website-tests`, and `website-syntax`; Basic Completion was accepted.
The verified build 2 was packaged with `build-dmg.sh --skip-build`. Image checksum verification and
read-only mounting passed. The contained app signature, build number 2, `/Applications` link, and
bilingual installation instructions were checked. Built and mounted executable SHA-256 both equal
`f7d9a89651e64e60766918eaadab7dd3520c4f23214ee33b3e4f468d7b2f5da1`.
DMG SHA-256 is `038aedb6df19a8ab9fa2479bebf96fe7c69065a358382d8d4ee59bfd13d7b92f`.
Build 2 contains the native logic manually verified above; this step did not reinstall the existing app
or verify download/launch on another Mac.

Publication verification is complete. After [PR #3](https://github.com/jgoneit/tessera/pull/3) passed its web CI,
[alpha.2](https://github.com/jgoneit/tessera/releases/tag/v0.1.0-alpha.2) was published as a prerelease from
source commit `31372b56b1cefde6cea2bd9d9f710066eab39949`. The public DMG and `SHA256SUMS` were downloaded
again without authentication and their checksum matched. The PR was then merged;
[Pages run 35445181648](https://github.com/jgoneit/tessera/actions/runs/35445181648) succeeded for merge
commit `09472a7366929434e0297874789a78646ca6965b`.

The public [Korean page](https://jgoneit.github.io/tessera/?lang=ko#demo) confirmed maximize→left 2×2 column
and maximize→top half. Switching to [English](https://jgoneit.github.io/tessera/?lang=en#demo) preserved the
state and continued top half→maximize→bottom half. The download button points to the alpha.2 DMG;
no browser warning/error logs appeared during these checks. Alpha.1 and the currently installed app remain
unchanged. Public-page verification does not establish installation/launch on another Mac or completion of
multi-display runtime coverage.
