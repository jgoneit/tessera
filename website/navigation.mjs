const SUPPORTED_LAYOUTS = [2, 3, 4];
const HEIGHTS = ['top', 'full', 'bottom'];

function enabledLayouts(layouts) {
  const enabled = SUPPORTED_LAYOUTS.filter((columns) => Array.isArray(layouts) && layouts.includes(columns));
  return enabled.length ? enabled : [3];
}

/** The same normalized column-center ordering used by Tessera's GridNavigation. */
export function candidates(layouts = [3]) {
  return enabledLayouts(layouts)
    .flatMap((columns) => Array.from({ length: columns }, (_, index) => ({
      columns,
      column: index + 1,
      center: (2 * index + 1) / (2 * columns),
    })))
    .sort((left, right) => (
      (2 * left.column - 1) * right.columns - (2 * right.column - 1) * left.columns
      || left.columns - right.columns
    ));
}

function nearestCandidate(choices, center) {
  let index = 0;
  for (let next = 1; next < choices.length; next += 1) {
    const boundary = choices[next - 1].center + (choices[next].center - choices[next - 1].center) / 2;
    if (center <= boundary) break;
    index = next;
  }
  return choices[index];
}

function stateAt(layouts, candidate, height, screenWidth = false) {
  return { layouts, columns: candidate.columns, column: candidate.column, height, screenWidth };
}

/** Start with a full-height column nearest the middle; exact ties go left. */
export function createState(layouts = [3]) {
  const enabled = enabledLayouts(layouts);
  return stateAt(enabled, nearestCandidate(candidates(enabled), 0.5), 'full');
}

/** Fill the usable screen; repeated commands never restore a prior placement. */
export function maximize(state) {
  return stateAt([...state.layouts], nearestCandidate(candidates(state.layouts), 0.5), 'full', true);
}

export function move(state, direction) {
  if (direction === 'left' || direction === 'right') {
    const choices = candidates(state.layouts);
    if (state.screenWidth) {
      const destination = direction === 'left'
        ? choices.findLast(candidate => candidate.center < 0.5) ?? choices.at(-1)
        : choices.find(candidate => candidate.center > 0.5) ?? choices[0];
      return stateAt([...state.layouts], destination, state.height);
    }
    const current = choices.findIndex(({ columns, column }) => columns === state.columns && column === state.column);
    const offset = direction === 'left' ? -1 : 1;
    const next = (current + offset + choices.length) % choices.length;
    return stateAt([...state.layouts], choices[next], state.height);
  }
  if (direction === 'up' || direction === 'down') {
    const current = HEIGHTS.indexOf(state.height);
    const next = Math.max(0, Math.min(HEIGHTS.length - 1, current + (direction === 'up' ? -1 : 1)));
    return next === current ? state : { ...state, layouts: [...state.layouts], height: HEIGHTS[next] };
  }
  return state;
}

/** Zone identifiers are row-major, with the upper row numbered first. */
export function selectZone(state, id) {
  if (!Number.isInteger(id) || id < 1 || id > state.columns * 2) return state;
  return {
    ...state,
    layouts: [...state.layouts],
    column: ((id - 1) % state.columns) + 1,
    height: id <= state.columns ? 'top' : 'bottom',
    screenWidth: false,
  };
}

/** Prefer a newly enabled grid, retaining screen-wide placement when active. */
export function setLayouts(state, layouts, preferredColumns) {
  const enabled = enabledLayouts(layouts);
  const center = state.screenWidth ? 0.5 : (2 * state.column - 1) / (2 * state.columns);
  const choices = candidates(enabled.includes(preferredColumns) ? [preferredColumns] : enabled);
  return stateAt(enabled, nearestCandidate(choices, center), state.height, state.screenWidth);
}

export function selectedZones(state) {
  if (state.screenWidth) {
    const start = state.height === 'bottom' ? state.columns + 1 : 1;
    const length = state.height === 'full' ? state.columns * 2 : state.columns;
    return Array.from({ length }, (_, index) => start + index);
  }
  if (state.height === 'top') return [state.column];
  if (state.height === 'bottom') return [state.columns + state.column];
  return [state.column, state.columns + state.column];
}

function partition(length, count, index) {
  const base = Math.floor(length / count);
  const remainder = length % count;
  return { offset: index * base + Math.min(index, remainder), length: base + (index < remainder ? 1 : 0) };
}

/**
 * Return a top-left-origin preview rectangle in logical pixels.
 * Bounds round inward, then remaining backing pixels are distributed from
 * left to right/top to bottom, matching the native geometry calculation.
 */
export function frame(state, { width = 1000, height = 500, gap = 8, scale = 1 } = {}) {
  if (![width, height, gap, scale].every(Number.isFinite)
    || width <= 0 || height <= 0 || gap < 0 || scale <= 0) {
    throw new RangeError('Invalid preview dimensions, gap, or scale');
  }
  const maximized = state.screenWidth && state.height === 'full';
  const effectiveGap = maximized ? 0 : gap;
  if (![width * scale, height * scale, effectiveGap * scale].every((value) => value <= 2 ** 52)) {
    throw new RangeError('Preview dimensions exceed the supported pixel range');
  }
  const pixelWidth = Math.floor(width * scale);
  const pixelHeight = Math.floor(height * scale);
  const pixelGap = Math.round(effectiveGap * scale);
  const columns = state.screenWidth ? 1 : state.columns;
  const rows = maximized ? 1 : 2;
  const column = state.screenWidth ? 0 : state.column - 1;
  const availableWidth = pixelWidth - (columns + 1) * pixelGap;
  const availableHeight = pixelHeight - (rows + 1) * pixelGap;
  if (availableWidth < columns || availableHeight < rows) {
    throw new RangeError('Not enough space for the selected grid and gaps');
  }
  const horizontal = partition(availableWidth, columns, column);
  const x = pixelGap + horizontal.offset + column * pixelGap;
  if (state.height === 'full') {
    return { x: x / scale, y: pixelGap / scale, width: horizontal.length / scale, height: (pixelHeight - 2 * pixelGap) / scale };
  }
  const row = state.height === 'top' ? 0 : 1;
  const vertical = partition(availableHeight, 2, row);
  return {
    x: x / scale,
    y: (pixelGap + vertical.offset + row * pixelGap) / scale,
    width: horizontal.length / scale,
    height: vertical.length / scale,
  };
}
