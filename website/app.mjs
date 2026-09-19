import { createState, move, selectZone, setLayouts, selectedZones, frame } from './navigation.mjs';

const root = document.documentElement;
const themeButton = document.querySelector('#themeToggleBtn');
const colorScheme = window.matchMedia('(prefers-color-scheme: dark)');
let chosenTheme;
try { chosenTheme = localStorage.getItem('tessera-website-theme'); } catch { /* Storage is optional. */ }
function renderTheme(theme) {
  const light = theme === 'light';
  root.classList.toggle('light', light);
  root.classList.toggle('dark', !light);
  document.querySelector('#themeIcon').textContent = light ? '☾' : '☼';
  themeButton.setAttribute('aria-label', light ? '다크 테마로 전환' : '라이트 테마로 전환');
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

const interaction = document.querySelector('.demo-interaction');
const stage = document.querySelector('#desktopStage');
const demoWindow = document.querySelector('#demoWindow');
const guides = document.querySelector('#layoutGuides');
const cards = document.querySelector('#hudCards');
const layoutInputs = [...document.querySelectorAll('input[name="layout"]')];
const directionButtons = [...document.querySelectorAll('[data-direction]')];
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
    cards.setAttribute('aria-label', `${state.columns}×2 격자 영역 선택`);
    for (let id = 1; id <= state.columns * 2; id++) {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'hud-card';
      button.dataset.zone = id;
      button.textContent = id;
      const column = (id - 1) % state.columns + 1;
      button.setAttribute('aria-label', `${id}번 영역, ${column}열 ${id <= state.columns ? '위칸' : '아래칸'}`);
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

  const activeIDs = selectedZones(state);
  cards.querySelectorAll('[data-zone]').forEach(button => {
    const active = activeIDs.includes(Number(button.dataset.zone));
    button.classList.toggle('active', active);
    button.setAttribute('aria-pressed', String(active));
  });
  const highlight = cards.querySelector('.hud-highlight');
  const cellWidth = (cards.clientWidth - 5 * (state.columns - 1)) / state.columns;
  Object.assign(highlight.style, {
    left: `${(state.column - 1) * (cellWidth + 5)}px`, width: `${cellWidth}px`,
    top: state.height === 'bottom' ? '41px' : '0px', height: state.height === 'full' ? '77px' : '36px'
  });

  const heightName = { top: '위칸', full: '전체', bottom: '아래칸' }[state.height];
  document.querySelector('#currentLayout').textContent = `${state.columns}×2`;
  document.querySelector('#selectionLabel').textContent = `${state.columns}×2 · ${state.column}열 ${heightName}`;
  document.querySelectorAll('[data-height]').forEach(label => label.classList.toggle('active', label.dataset.height === state.height));
  Object.assign(demoWindow.dataset, { layout: `${state.columns}x2`, column: state.column, height: state.height });
  layoutInputs.forEach(input => {
    input.checked = state.layouts.includes(Number(input.value));
    input.disabled = input.checked && state.layouts.length === 1;
  });
  renderFrame();
}

function navigate(direction) {
  state = move(state, direction);
  render();
}

layoutInputs.forEach(input => input.addEventListener('change', () => {
  const layouts = layoutInputs.filter(item => item.checked).map(item => Number(item.value));
  if (layouts.length) state = setLayouts(state, layouts, input.checked ? Number(input.value) : undefined);
  render();
}));
directionButtons.forEach(button => button.addEventListener('click', () => {
  button.focus({ preventScroll: true });
  navigate(button.dataset.direction);
}));
cards.addEventListener('click', event => {
  const button = event.target.closest('[data-zone]');
  if (!button) return;
  button.focus({ preventScroll: true });
  state = selectZone(state, Number(button.dataset.zone));
  render();
});
stage.addEventListener('click', () => interaction.focus({ preventScroll: true }));
document.addEventListener('pointerdown', event => {
  if (!interaction.contains(event.target) && interaction.contains(document.activeElement)) {
    document.activeElement.blur();
  }
});

const directions = { ArrowLeft: 'left', ArrowRight: 'right', ArrowUp: 'up', ArrowDown: 'down' };
const clearPressed = () => directionButtons.forEach(button => button.classList.remove('is-pressed'));
interaction.addEventListener('keydown', event => {
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
interaction.addEventListener('keyup', clearPressed);
interaction.addEventListener('focusout', clearPressed);
window.addEventListener('blur', clearPressed);
document.addEventListener('visibilitychange', clearPressed);
new ResizeObserver(() => render()).observe(stage);
render();
