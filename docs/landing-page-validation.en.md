# Landing page prototype and deployment validation — 2026-09-19

[한국어](landing-page-validation.md) | English

## Scope

- Preserved the dark/light colors, grid background, heading, and download flow from the user-provided ZIP.
- Removed the sections promoting the technology stack, security, performance figures, and checksums, along with the nonexistent license link.
- Added a separate static page in `website/`. The original ZIP, native app source,
  installed `/Applications/Tessera.app`, distributed DMG, and GitHub Release were unchanged.
- The download link points to the existing public `v0.1.0-alpha.1` release.
  The site was not deployed during the initial prototype validation. The GitHub Pages
  deployment configuration below was added later at the user's request.

## Automated checks

- `node --test website/navigation.test.mjs`: 16 tests passed.
  Coverage included all 7 nonempty grid combinations, horizontal wraparound and height preservation,
  the right half in 2×2+3×2, top/full/bottom transitions and endpoints, row-major numbering,
  settings changes, full-column frames that include the middle gap, and pixel alignment.
- `node --check website/app.mjs`: syntax check passed.
- Confirmed removal of technical/security marketing, unsupported performance figures, the incorrect checksum, and MIT License wording from the HTML.

## Browser validation

Opened the page through a local HTTP server in the Codex in-app browser.

- Checked 1280×900 desktop dark/light views and 390×844 and 320×740 light views.
  On narrow screens, document scrollWidth equaled viewport width, with no horizontal overflow.
- In the initial 3×2 state, zones 2 and 5 were highlighted with one continuous outline,
  and the example window filled the entire middle column.
- Clicking `↑ ↓ ↓ ↓ ↑` produced top → full → bottom → bottom → full.
- After also selecting 2×2, moving right from the middle third produced
  `2×2 · 2열 전체` (2×2 · column 2, full height), and numbering changed to 1–4.
- With only 4×2 selected, 1–4 appeared in the top row and 5–8 in the bottom row.
  The last selected grid's checkbox was disabled to prevent an empty selection.
- After clicking a direction button, pressing keyboard ↑ moved up one height step.
- Entering `2`, `↓`, `↓` moved top → full → bottom.
- Direction keys held with Control were not handled by the web demo, leaving the selection unchanged.
- After Esc or a click outside the demo, focus was outside the demo area.
- The browser error log was empty at the time of inspection.

## Seal and validation limits

Basic Task `tessera-landing-demo-20260919` uses the existing catalog's `unit-tests`
and `app-bundle` checks (300 seconds each). These validate the existing Swift app's
regressions and bundle; they do not replace the web model tests and browser checks above.
The exact Run and Completion results are recorded in that Seal Task.

The web demo moves one example window without moving any real windows. It keeps the
selector open after a number or click so visitors can continue trying it, rather than
reproducing the native app's selector dismissal. AX permission, actual app minimum sizes,
native key repeat, Korean input, and multiple displays are outside the scope of this web
prototype. Existing incomplete multi-display checks remain incomplete.
Separate Safari/Chrome sessions and direct VoiceOver operation were not tested.

## GitHub Pages deployment preparation

- Added an automatic deployment workflow while preserving the approved prototype and native app.
- Only the five required static files are copied into the deployment directory. Tests,
  the README, and app repository contents are excluded from the deployed site.
- Confirmed that all required files and module imports use relative paths for the `/tessera/` base path.
- Anonymous HTTP requests to the external download, installation guide, and repository links returned 200.
- Reran and passed the 16 web tests and JavaScript syntax check before deployment.
- New Basic Task `tessera-github-pages-20260919` retains the two existing required app checks.
  Web behavior is validated separately through Node checks and browser inspection.
- Deployment results are recorded in the `Publish Tessera website` GitHub Actions run.
  The public URL, module responses, and demo interactions are checked separately after publication.

## Initial publication and grid-selection refinement

- The Actions run for initial publication commit `158463d2d18a92365fbcb36b0d26fbf05f32d476`
  succeeded: <https://github.com/jgoneit/tessera/actions/runs/35437511529>.
- The five public files at <https://jgoneit.github.io/tessera/> returned HTTP 200 to
  anonymous requests and matched the files in that commit. `.mjs` responses used `text/javascript`.
- At the user's additional request, checking a grid now immediately makes it the previewed grid.
  Previously selected grids and the height state are preserved; subsequent direction input visits all selected grids.
- All 19 Node tests passed, including 3 additional regression tests.
- In the local browser, checking 2×2 from the initial 3×2 state immediately showed `2×2 · 1열 전체`
  (2×2 · column 1, full height). After moving to the bottom row, checking 4×2 immediately showed
  `4×2 · 1열 아래칸` (4×2 · column 1, bottom) with 8 numbers. All three grids remained selected,
  and the next → input moved to `3×2 · 1열 아래칸` (3×2 · column 1, bottom).
- This refinement is validated separately under Basic Task `tessera-preview-layout-selection-20260919`.

## Direction-key interaction immediately after grid selection

- Included the checkbox toolbar in the same keyboard demo scope. After selection, focus remains
  on the checkbox so direction keys work without another click; native Tab/Space behavior is preserved.
- In the local in-app browser, focus remained on the input immediately after checking 2×2.
  Pressing → moved from `2×2 · 1열 전체` (2×2 · column 1, full height) to `3×2 · 2열 전체` (3×2 · column 2, full height).
- Pressing ↑/↓ on the same checkbox moved to top/full height while scrollY stayed unchanged.
- After unchecking 2×2 with Space, ← still worked. Tab skipped the disabled last-selected
  3×2 checkbox and moved to 4×2; selecting it with Space and pressing ↓ placed the example in the bottom row.
- After Esc, focus returned to BODY. Direction keys on the theme button outside the demo
  did not change the demo selection.
- The existing 19 Node tests and JavaScript syntax check passed. This change is validated
  separately under Basic Task `tessera-preview-keyboard-handoff-20260919`.
- At the first public check, HTML had updated but keyboard behavior in a previously opened tab
  remained stale. Added a content-hash version to the app script URL to distinguish cached versions.
