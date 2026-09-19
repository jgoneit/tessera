import { createState, maximize, move, selectZone, setLayouts, selectedZones, frame } from './navigation.mjs?v=bd4bcbeb0add';

import { resolveLanguage, t, translateDocument } from './i18n.mjs?v=206e36eacc6e';

const root = document.documentElement;
const languageButton = document.querySelector('#languageToggleBtn');
let savedLanguage;
try { savedLanguage = localStorage.getItem('tessera-website-language.v1'); } catch { /* Storage is optional. */ }
let language = resolveLanguage({
  requested: new URL(window.location.href).searchParams.get('lang'),
  saved: savedLanguage,
  preferred: navigator.languages
});
const text = (key, values) => t(language, key, values);
const themeButton = document.querySelector('#themeToggleBtn');
const colorScheme = window.matchMedia('(prefers-color-scheme: dark)');
let chosenTheme;
try { chosenTheme = localStorage.getItem('tessera-website-theme'); } catch { /* Storage is optional. */ }
function renderTheme(theme) {
  const light = theme === 'light';
  root.classList.toggle('light', light);
  root.classList.toggle('dark', !light);
  document.querySelector('#themeIcon').textContent = light ? '☾' : '☼';
  themeButton.setAttribute('aria-label', text(light ? 'theme.dark' : 'theme.light'));
}
renderTheme(['light', 'dark'].includes(chosenTheme) ? chosenTheme : colorScheme.matches ? 'dark' : 'light');
themeButton.addEventListener('click', () => {
  chosenTheme = root.classList.contains('light') ? 'dark' : 'light';
  renderTheme(chosenTheme);
  try { localStorage.setItem('tessera-website-theme', chosenTheme); } catch { /* Keep the in-page preference. */ }
});
colorScheme.addEventListener('change', () => {
  if (!['light', 'dark'].includes(chosenTheme)) renderTheme(colorScheme.matches ? 'dark' : 'light');
});

const demo = document.querySelector('#demo');
const interaction = document.querySelector('.demo-interaction');
const stage = document.querySelector('#desktopStage');
const demoWindow = document.querySelector('#demoWindow');
const guides = document.querySelector('#layoutGuides');
const cards = document.querySelector('#hudCards');
const layoutInputs = [...document.querySelectorAll('input[name="layout"]')];
const directionButtons = [...document.querySelectorAll('[data-direction]')];
const maximizeButton = document.querySelector('#maximizeBtn');
let state = createState([3]);
let renderedColumns = 0;

function renderFrame() {
  const bounds = frame(state, { width: stage.clientWidth, height: stage.clientHeight, gap: 8, scale: window.devicePixelRatio || 1 });
  Object.assign(demoWindow.style, { left: `${bounds.x}px`, top: `${bounds.y}px`, width: `${bounds.width}px`, height: `${bounds.height}px` });
}

function render() {
  if (renderedColumns !== state.columns) {
    const hadZoneFocus = cards.contains(document.activeElement);
    cards.replaceChildren();
    guides.replaceChildren();
    cards.style.gridTemplateColumns = `repeat(${state.columns}, 1fr)`;
    guides.style.gridTemplateColumns = `repeat(${state.columns}, 1fr)`;
    for (let id = 1; id <= state.columns * 2; id++) {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'hud-card';
      button.dataset.zone = id;
      button.textContent = id;
      cards.append(button);
      const guide = document.createElement('div');
      guide.className = 'layout-guide';
      guides.append(guide);
    }
    const highlight = document.createElement('div');
    highlight.className = 'hud-highlight';
    highlight.setAttribute('aria-hidden', 'true');
    cards.append(highlight);
    renderedColumns = state.columns;
    if (hadZoneFocus) interaction.focus({ preventScroll: true });
  }

  cards.setAttribute('aria-label', text('grid.label', { columns: state.columns }));
  const activeIDs = selectedZones(state);
  cards.querySelectorAll('[data-zone]').forEach(button => {
    const id = Number(button.dataset.zone);
    button.setAttribute('aria-label', text('zone.label', {
      id, column: (id - 1) % state.columns + 1,
      height: text(id <= state.columns ? 'height.top' : 'height.bottom')
    }));
    const active = activeIDs.includes(id);
    button.classList.toggle('active', active);
    button.setAttribute('aria-pressed', String(active));
  });
  const highlight = cards.querySelector('.hud-highlight');
  const cellWidth = (cards.clientWidth - 5 * (state.columns - 1)) / state.columns;
  Object.assign(highlight.style, {
    left: state.screenWidth ? '0px' : `${(state.column - 1) * (cellWidth + 5)}px`,
    width: state.screenWidth ? `${cards.clientWidth}px` : `${cellWidth}px`,
    top: state.height === 'bottom' ? '41px' : '0px', height: state.height === 'full' ? '77px' : '36px'
  });

  const heightName = text(`height.${state.height}`);
  document.querySelector('#currentLayout').textContent = state.screenWidth ? text('screen.label') : `${state.columns}×2`;
  document.querySelector('#selectionLabel').textContent = state.screenWidth
    ? text(`screen.${state.height}`)
    : text('selection', { columns: state.columns, column: state.column, height: heightName });
  document.querySelectorAll('.height-guide [data-height]').forEach(label => {
    label.classList.toggle('active', label.dataset.height === state.height);
    label.textContent = text(`${state.screenWidth ? 'screen' : 'height'}.${label.dataset.height}`);
  });
  maximizeButton.setAttribute('aria-pressed', String(Boolean(state.screenWidth && state.height === 'full')));
  Object.assign(demoWindow.dataset, { layout: `${state.columns}x2`, column: state.column, height: state.height, screenWidth: String(Boolean(state.screenWidth)) });
  layoutInputs.forEach(input => {
    input.checked = state.layouts.includes(Number(input.value));
    input.disabled = input.checked && state.layouts.length === 1;
  });
  renderFrame();
}

function renderLanguage() {
  translateDocument(document, language);
  languageButton.lang = language === 'ko' ? 'en' : 'ko';
  renderTheme(root.classList.contains('light') ? 'light' : 'dark');
  render();
}
languageButton.addEventListener('click', () => {
  language = language === 'ko' ? 'en' : 'ko';
  savedLanguage = language;
  try { localStorage.setItem('tessera-website-language.v1', language); } catch { /* Keep the in-page preference. */ }
  const url = new URL(window.location.href);
  url.searchParams.set('lang', language);
  window.history.replaceState(null, '', url);
  renderLanguage();
});

window.addEventListener('popstate', () => {
  language = resolveLanguage({
    requested: new URL(window.location.href).searchParams.get('lang'),
    saved: savedLanguage,
    preferred: navigator.languages
  });
  renderLanguage();
});

function navigate(direction) {
  state = move(state, direction);
  render();
}

layoutInputs.forEach(input => input.addEventListener('change', () => {
  const layouts = layoutInputs.filter(item => item.checked).map(item => Number(item.value));
  if (layouts.length) state = setLayouts(state, layouts, input.checked ? Number(input.value) : undefined);
  render();
  input.focus({ preventScroll: true });
}));
directionButtons.forEach(button => button.addEventListener('click', () => {
  button.focus({ preventScroll: true });
  navigate(button.dataset.direction);
}));
maximizeButton.addEventListener('click', () => {
  maximizeButton.focus({ preventScroll: true });
  state = maximize(state);
  render();
});
cards.addEventListener('click', event => {
  const button = event.target.closest('[data-zone]');
  if (!button) return;
  button.focus({ preventScroll: true });
  state = selectZone(state, Number(button.dataset.zone));
  render();
});
stage.addEventListener('click', () => interaction.focus({ preventScroll: true }));
document.addEventListener('pointerdown', event => {
  if (!demo.contains(event.target) && demo.contains(document.activeElement)) {
    document.activeElement.blur();
  }
});

const directions = { ArrowLeft: 'left', ArrowRight: 'right', ArrowUp: 'up', ArrowDown: 'down' };
const clearPressed = () => directionButtons.forEach(button => button.classList.remove('is-pressed'));
demo.addEventListener('keydown', event => {
  // The website demo never intercepts Tessera's real global shortcuts.
  if (event.ctrlKey || event.altKey || event.metaKey || event.shiftKey || event.isComposing) return;
  const direction = directions[event.key];
  if (direction) {
    event.preventDefault();
    if (event.repeat && (direction === 'up' || direction === 'down')) return;
    clearPressed();
    directionButtons.find(button => button.dataset.direction === direction).classList.add('is-pressed');
    navigate(direction);
  } else if (/^(Digit|Numpad)[1-8]$/.test(event.code)) {
    const id = Number(event.code.slice(-1));
    if (id > state.columns * 2) return;
    event.preventDefault();
    state = selectZone(state, id);
    render();
  } else if (event.key === 'Escape') {
    document.activeElement?.blur();
    clearPressed();
  }
});
demo.addEventListener('keyup', clearPressed);
demo.addEventListener('focusout', clearPressed);
window.addEventListener('blur', clearPressed);
document.addEventListener('visibilitychange', clearPressed);
new ResizeObserver(() => render()).observe(stage);
renderLanguage();
