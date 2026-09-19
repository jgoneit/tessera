# English documentation and website validation

[한국어](bilingual-validation.md) | English

Validated on 2026-09-19. English support was added alongside the existing Korean documentation
and website. The native app and release DMG were not changed. Outstanding native checks remain
in the [native validation record](validation.en.md).

## Automated checks

- `node --test website/*.test.mjs`: 28 tests passed: 19 existing navigation tests, eight translation
  tests, and one deployment asset cache-version test.
- Checked matching translation keys and parameters, HTML bindings, URL/stored/browser language
  precedence, placement and cell names for all three grids, and updates to visible text,
  accessible names, and metadata.
- `node --check website/app.mjs` and `node --check website/i18n.mjs` passed.
- Compared English documentation sections, commands, and record identifiers with the originals.
  Historical test counts and limitations retain their original context. All 26 local links across 12 documents
  and `git diff --check` passed.

## Local browser checks

Verified through actual UI interactions in the Codex in-app browser.

- Switched between Korean/English and light/dark themes. Checked text and controls at desktop
  width (1280px) and narrow widths (375px and 320px), with no horizontal page overflow. On narrow
  screens, the header download uses an icon with an accessible name; the main download keeps its text.
- Language changes preserved 2×2+3×2 or all selected grids and the top/full-column/bottom state.
  Arrow keys worked immediately after checking a grid. In 4×2, pressing 8 selected a bottom cell;
  pressing Up once then selected its full column.
- Changing language without changing the column count updated every cell's accessible name and
  the current placement label. The only Korean text on the English page was the intended language button.
- Reloading or opening a URL with no language parameter applied the stored selection.
  Explicit `?lang=ko`/`?lang=en` took precedence over the stored preference.
- After navigating to an anchor, changing language, and going back, the URL and displayed language
  agreed while selected grids and placement were preserved. No browser console errors were recorded.

## Validation boundaries

- These results cover browser behavior and static translations. VoiceOver interaction and other
  browser engines were not tested in this pass. They do not replace native window-placement or
  external-display validation.
- Link-preview services that do not run JavaScript may use Korean static metadata even for an English
  URL. With JavaScript disabled, downloads and links to Korean/English documentation remain available.
