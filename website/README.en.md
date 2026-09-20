# Tessera website

[한국어](README.md) | English

A static landing page based on the colors, typography, cards, and download flow in the
user-supplied `tessera---macos-grid-window-manager.zip`. The original ZIP has not been modified.
The public website is <https://jgoneit.github.io/tessera/>. Local previews and GitHub Pages
deployments use the same files.

Run this command from the repository root, then open the address in your browser:

```sh
python3 -m http.server 8080 --bind 127.0.0.1 --directory website
```

Visit `http://127.0.0.1:8080`. Since the page uses ES modules, serve it over HTTP instead of
opening the HTML file directly. No package installation or build is required.

## Demo

- Select any combination of 2×2, 3×2, and 4×2. The last selected grid cannot be deselected.
- Selecting a new grid immediately previews its nearest column. Existing grid selections
  and the height state are preserved; subsequent horizontal navigation visits all selected grids.
- Left and right follow the horizontal order of the selected grids' column centers and wrap at either end.
- Up and down move one step at a time through top cell ↔ full column ↔ bottom cell, stopping at the ends.
- Press Return while the demo area or a grid checkbox has focus to maximize. The Maximize button
  is also available. Maximizing fills the usable area without a gap; up/down then move between
  screen halves and maximized, while left/right return to a grid and preserve the height state.
- Cells are numbered from the top row: 1–4, 1–6, or 1–8. Full-column selection highlights both rows with a connected outline.
- Arrow and number keys are handled only while a grid checkbox or the demo area has focus.
  After choosing a grid, use the arrow keys without an extra click. Checkbox focus is preserved,
  so Tab/Shift+Tab and Space remain available to select other grids. Up/down key repeats are ignored.
  Press Esc or click outside the demo to resume normal page navigation.
- Clicking a direction/cell button with the pointer, or using arrow/number keys from that button,
  moves focus into the demo so Return is immediately available. Enter/Space still activate buttons
  selected with Tab. Repeated Return in the demo area is ignored; modified keys and IME
  composition events are left untouched.
- Number and click selections keep the web preview open for repeated interaction. This differs from
  the native app's picker, which closes after placing a window by number or click.
- The demo starts at an explicit central column. It does not reproduce AX window capture,
  frame recognition, or app constraints. It uses a browser model separate from the native app code.

## Language

The **EN / 한국어** button at the top switches the introduction, installation instructions,
current demo placement, and accessible names together. Selected grids, the current column and
height, and the theme are preserved.

- [한국어](https://jgoneit.github.io/tessera/?lang=ko) · [English](https://jgoneit.github.io/tessera/?lang=en)
- Language priority is a supported `lang` URL value → saved choice → first supported browser language.
  English is used if none is supported. Selecting a language with the button saves it in the browser.
- Translations are maintained in `i18n.mjs`. Static HTML defaults to Korean; JavaScript also updates
  the document language, title, and description. Link previews that do not execute JavaScript may
  show a Korean title even for an English URL.
- Downloads and links to Korean and English documentation remain available when JavaScript is disabled.

## Verification

For the Return-to-maximize change on 2026-09-20, all 49 web tests and the JavaScript syntax check passed.
Local browser checks covered Return after grid selection or arrow navigation, numpad Enter,
horizontal/vertical movement after maximizing, pointer placement followed by Return, native
Enter/Space on Tab-selected buttons, untouched Control+Option+Return, and inactive Return after Esc.
Korean/English copy and the English light theme at 320px were checked without horizontal overflow.
Physical key repeat, Korean IME, and other browser engines were not separately tested in this change.

```sh
node --test website/*.test.mjs
```

The [website validation record](../docs/landing-page-validation.en.md) documents the existing app's
Seal checks and the scope of web verification. The [bilingual support validation record](../docs/bilingual-validation.en.md)
separately records translation and language-switching verification for this change.
Download links target version `v0.1.0-alpha.4`. When switching to a new release,
update both download links and the installation guide link together. The alpha.4 asset is
`Tessera-0.1.0-alpha.4-arm64.dmg`, used for both direct downloads and in-app updates.
Users on alpha.3 or earlier must install alpha.4 manually once. See the
[installation guide](../docs/INSTALL.en.md#update-tessera) for background checking and installation behavior.
When changing `app.mjs`, also update the `v` in its script URL in `index.html` to the first 12 characters
of the file's SHA-256. This prevents returning visitors from continuing to run an older cached script.
When changing `navigation.mjs` or `i18n.mjs`, update the corresponding import URL version before
updating the app version. Version the `styles.css` stylesheet URL in the HTML the same way.
`assets.test.mjs` checks that each version matches the actual file contents.

## GitHub Pages

When page or workflow files change on `main`, `.github/workflows/pages.yml` deploys files to GitHub Pages
only after they pass the Node tests and syntax checks. Pull requests run preparation and checks only.
The workflow can also be run manually from Actions.

Published files are `index.html`, `styles.css`, `app.mjs`, `navigation.mjs`, `i18n.mjs`, `mark.svg`,
the signed `appcast.xml`, and the `.nojekyll` file generated by the workflow. Tests, documentation, and native app files are not
deployed to the website. The repository's Pages Source setting is **GitHub Actions**.

`appcast.xml` has the fixed URL `https://jgoneit.github.io/tessera/appcast.xml`.
Sparkle's release tools generate it with Korean/English release notes and the DMG signature, then sign the feed itself.
Do not edit the final signed feed directly; regenerate it with the existing update key from the login keychain.
Never include the private key in website files or the repository. Publish and verify the actual DMG on GitHub Releases
before deploying its download links and feed to Pages. Withdrawing an update also requires signing the revised feed.

Relative file references support both the `/tessera/` path and the root of a separate domain.
To connect a domain, configure both GitHub Pages' **Custom domain** setting and the domain's DNS.
Actions deployments do not require a CNAME file.
Official guide: <https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site>
