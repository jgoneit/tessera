import test from 'node:test';
import assert from 'node:assert/strict';
import { candidates, createState, maximize, move, selectZone, setLayouts, selectedZones, frame } from './navigation.mjs';

const orderings = [
  [[2], ['2:1', '2:2']],
  [[3], ['3:1', '3:2', '3:3']],
  [[4], ['4:1', '4:2', '4:3', '4:4']],
  [[2, 3], ['3:1', '2:1', '3:2', '2:2', '3:3']],
  [[2, 4], ['4:1', '2:1', '4:2', '4:3', '2:2', '4:4']],
  [[3, 4], ['4:1', '3:1', '4:2', '3:2', '4:3', '3:3', '4:4']],
  [[2, 3, 4], ['4:1', '3:1', '2:1', '4:2', '3:2', '4:3', '2:2', '3:3', '4:4']],
];
const identity = ({ columns, column }) => `${columns}:${column}`;

for (const [layouts, expected] of orderings) {
  test(`${layouts.join('+')} columns: ordered traversal wraps and preserves each height`, () => {
    assert.deepEqual(candidates(layouts).map(identity), expected);
    assert.deepEqual(candidates([...layouts].reverse().concat(layouts)).map(identity), expected);
    for (const height of ['top', 'full', 'bottom']) {
      const first = candidates(layouts)[0];
      let state = { layouts, columns: first.columns, column: first.column, height, screenWidth: false };
      for (const destination of [...expected.slice(1), expected[0]]) {
        state = move(state, 'right');
        assert.equal(identity(state), destination);
        assert.equal(state.height, height);
      }
      for (const destination of [...expected.slice(1).reverse(), expected[0]]) {
        state = move(state, 'left');
        assert.equal(identity(state), destination);
        assert.equal(state.height, height);
      }
    }
  });
}

test('initial selection is nearest the center, ties left, and resets to full', () => {
  assert.deepEqual(createState([2]), { layouts: [2], columns: 2, column: 1, height: 'full', screenWidth: false });
  assert.deepEqual(createState([4]), { layouts: [4], columns: 4, column: 2, height: 'full', screenWidth: false });
  assert.deepEqual(createState([2, 3, 4]), { layouts: [2, 3, 4], columns: 3, column: 2, height: 'full', screenWidth: false });
  assert.equal(move(createState(), 'up').height, 'top');
  assert.equal(createState().height, 'full');
  assert.deepEqual(createState([]), createState([3]));
  assert.deepEqual(createState([99, '2']), createState([3]));
  assert.deepEqual(createState([4, 2, 4]), createState([2, 4]));
});

test('2x2 + 3x2 moves through both halves and thirds in either direction', () => {
  let state = createState([2, 3]);
  const sequence = [];
  for (let step = 0; step < 5; step += 1) {
    state = move(state, 'right');
    sequence.push(identity(state));
  }
  assert.deepEqual(sequence, ['2:2', '3:3', '3:1', '2:1', '3:2']);
  state = move(move(createState([2, 3]), 'right'), 'right');
  assert.equal(identity(move(state, 'left')), '2:2');
});

test('vertical movement always passes through full and stops at endpoints', () => {
  for (const columns of [2, 3, 4]) {
    let state = move(createState([columns]), 'up');
    assert.equal(state.height, 'top');
    assert.equal(move(state, 'up'), state);
    const steps = [];
    for (const direction of ['down', 'down', 'down', 'up', 'up', 'up']) {
      state = move(state, direction);
      steps.push(state.height);
    }
    assert.deepEqual(steps, ['full', 'bottom', 'bottom', 'full', 'top', 'top']);
  }
});

test('zone selection and highlights use two rows with 4, 6, or 8 identifiers', () => {
  for (const columns of [2, 3, 4]) {
    const initial = createState([columns]);
    for (let id = 1; id <= columns * 2; id += 1) {
      const state = selectZone(initial, id);
      assert.deepEqual(selectedZones(state), [id]);
      assert.equal(state.column, ((id - 1) % columns) + 1);
      assert.equal(state.height, id <= columns ? 'top' : 'bottom');
      const full = move(state, state.height === 'top' ? 'down' : 'up');
      assert.deepEqual(selectedZones(full), [state.column, state.column + columns]);
    }
    for (const invalid of [0, -1, columns * 2 + 1, 1.5, NaN, '1']) {
      assert.equal(selectZone(initial, invalid), initial);
    }
  }
});

test('changing enabled grids chooses nearest prior center and retains height', () => {
  const rightHalf = selectZone(createState([2]), 4);
  const next = setLayouts(rightHalf, [3]);
  assert.deepEqual(next, { layouts: [3], columns: 3, column: 3, height: 'bottom', screenWidth: false });
  const centered = selectZone(createState([3]), 2);
  assert.deepEqual(setLayouts(centered, [2]), { layouts: [2], columns: 2, column: 1, height: 'top', screenWidth: false });
  assert.deepEqual(setLayouts(centered, []), centered);
  assert.deepEqual(setLayouts(centered, [3, 2, 3]).layouts, [2, 3]);
});

test('checking 2x2 immediately selects its nearest column with left tie-breaking', () => {
  const centered = move(createState([3]), 'up');
  const selected = setLayouts(centered, [3, 2], 2);
  assert.deepEqual(selected, { layouts: [2, 3], columns: 2, column: 1, height: 'top', screenWidth: false });
  assert.deepEqual(selectedZones(selected), [1]);
  assert.equal(centered.columns, 3);
});

test('checking 4x2 retains every enabled grid and height for the next arrow', () => {
  const centered = move(createState([2, 3]), 'down');
  const selected = setLayouts(centered, [2, 3, 4], 4);
  assert.deepEqual(selected, { layouts: [2, 3, 4], columns: 4, column: 2, height: 'bottom', screenWidth: false });
  assert.deepEqual(selectedZones(selected), [6]);
  assert.deepEqual(move(selected, 'right'), { layouts: [2, 3, 4], columns: 3, column: 2, height: 'bottom', screenWidth: false });
  assert.deepEqual(move(selected, 'left'), { layouts: [2, 3, 4], columns: 2, column: 1, height: 'bottom', screenWidth: false });
});

test('removing the active grid ignores a disabled preference and uses remaining candidates', () => {
  const selected = setLayouts(createState([2, 3]), [2, 3, 4], 4);
  const expected = { layouts: [2, 3], columns: 2, column: 1, height: 'full', screenWidth: false };
  assert.deepEqual(setLayouts(selected, [2, 3]), expected);
  assert.deepEqual(setLayouts(selected, [2, 3], 4), expected);
  assert.deepEqual(setLayouts(selected, [2, 3], 99), expected);
});

test('navigation returns new state without changing previous selection', () => {
  const initial = Object.freeze({ layouts: Object.freeze([2, 3]), columns: 3, column: 2, height: 'full', screenWidth: false });
  const right = move(initial, 'right');
  const upper = move(initial, 'up');
  assert.equal(identity(right), '2:2');
  assert.equal(upper.height, 'top');
  assert.deepEqual(initial, { layouts: [2, 3], columns: 3, column: 2, height: 'full', screenWidth: false });
  assert.equal(move(initial, 'unknown'), initial);
});

test('full-height frame spans both rows and their middle gap', () => {
  for (const columns of [2, 3, 4]) {
    const state = createState([columns]);
    const full = frame(state);
    const top = frame(move(state, 'up'));
    const bottom = frame(move(state, 'down'));
    assert.equal(full.x, top.x);
    assert.equal(full.width, top.width);
    assert.equal(full.y, top.y);
    assert.equal(bottom.y - (top.y + top.height), 8);
    assert.equal(full.height, top.height + 8 + bottom.height);
    assert.equal(full.y + full.height, bottom.y + bottom.height);
  }
});

test('geometry stays contained and pixel-aligned with shared zero-gap edges', () => {
  for (const columns of [2, 3, 4]) {
    for (const scale of [1, 2]) {
      for (const gap of [0, 4, 8, 12]) {
        const dimensions = { width: 901.25, height: 501.75, scale, gap };
        const initial = createState([columns]);
        for (let id = 1; id <= columns * 2; id += 1) {
          const rect = frame(selectZone(initial, id), dimensions);
          for (const value of Object.values(rect)) assert.ok(Number.isInteger(value * scale));
          assert.ok(rect.x >= gap && rect.y >= gap);
          assert.ok(rect.x + rect.width <= dimensions.width - gap);
          assert.ok(rect.y + rect.height <= dimensions.height - gap);
          if (id % columns !== 0) {
            const neighbor = frame(selectZone(initial, id + 1), dimensions);
            assert.equal(neighbor.x - (rect.x + rect.width), gap);
          }
        }
      }
    }
  }
});

test('geometry rejects invalid or unusable preview dimensions', () => {
  const state = createState();
  for (const options of [{ width: 0 }, { height: Infinity }, { gap: -1 }, { scale: 0 }, { width: 10 }, { width: 2 ** 53 }]) {
    assert.throws(() => frame(state, options), RangeError);
  }
});

for (const [layouts, ordering] of orderings) {
  test(`${layouts.join('+')} screen placements enter the nearest directional column and preserve height`, () => {
    const columns = layouts.includes(4) ? 4 : layouts.includes(2) ? 2 : 3;
    const expected = { left: `${columns}:${columns === 4 ? 2 : 1}`, right: `${columns}:${columns === 2 ? 2 : 3}` };
    for (const height of ['top', 'full', 'bottom']) {
      const screen = { ...maximize(createState(layouts)), height };
      for (const direction of ['left', 'right']) {
        let entered = move(screen, direction);
        assert.equal(identity(entered), expected[direction]);
        assert.equal(entered.height, height);
        assert.equal(entered.screenWidth, false);
        const first = entered;
        for (let step = 0; step < ordering.length; step += 1) {
          entered = move(entered, direction);
          assert.equal(entered.screenWidth, false);
          assert.equal(entered.height, height);
        }
        assert.deepEqual(entered, first);
      }
    }
  });

  test(`${layouts.join('+')} screen heights stop at endpoints and highlight complete rows`, () => {
    let state = maximize(createState(layouts));
    const preview = identity(state);
    const topIDs = Array.from({ length: state.columns }, (_, index) => index + 1);
    const bottomIDs = topIDs.map(id => id + state.columns);
    assert.deepEqual(selectedZones(state), [...topIDs, ...bottomIDs]);
    state = move(state, 'up');
    assert.equal(state.height, 'top');
    assert.equal(move(state, 'up'), state);
    assert.deepEqual(selectedZones(state), topIDs);
    state = move(state, 'down');
    assert.equal(state.height, 'full');
    assert.deepEqual(selectedZones(state), [...topIDs, ...bottomIDs]);
    state = move(state, 'down');
    assert.equal(state.height, 'bottom');
    assert.equal(move(state, 'down'), state);
    assert.deepEqual(selectedZones(state), bottomIDs);
    state = move(state, 'up');
    assert.equal(state.height, 'full');
    assert.equal(state.screenWidth, true);
    assert.equal(identity(state), preview);
  });
}

test('maximizing is repeatable, resets height, and chooses a center preview without mutating input', () => {
  for (const [layouts] of orderings) {
    const initial = Object.freeze({
      ...move(move(createState(layouts), 'right'), 'down'),
      layouts: Object.freeze([...layouts]),
    });
    const result = maximize(initial);
    assert.deepEqual(result, { ...createState(layouts), screenWidth: true });
    assert.deepEqual(maximize(result), result);
    assert.notEqual(result.layouts, initial.layouts);
    assert.equal(initial.height, 'bottom');
    assert.equal(initial.screenWidth, false);
    assert.deepEqual(maximize(move(result, 'up')), result);
    assert.equal(move(result, 'unknown'), result);
  }
});

test('selecting a zone leaves screen-wide mode in the displayed grid', () => {
  for (const columns of [2, 3, 4]) {
    for (const height of ['top', 'full', 'bottom']) {
      const screen = { ...maximize(createState([columns])), height };
      for (let id = 1; id <= columns * 2; id += 1) {
        assert.deepEqual(selectZone(screen, id), selectZone(createState([columns]), id));
      }
      for (const invalid of [0, -1, columns * 2 + 1, 1.5, NaN, '1']) {
        assert.equal(selectZone(screen, invalid), screen);
      }
      assert.equal(screen.screenWidth, true);
    }
  }
});

test('changing grids retains screen placement while updating its preview and next directional entry', () => {
  for (const height of ['top', 'full', 'bottom']) {
    const initial = Object.freeze({ ...maximize(createState([3])), height, layouts: Object.freeze([3]) });
    const both = setLayouts(initial, [3, 2], 2);
    assert.deepEqual(both, { layouts: [2, 3], columns: 2, column: 1, height, screenWidth: true });
    assert.deepEqual(frame(both), frame(initial));
    assert.equal(identity(move(both, 'left')), '2:1');
    assert.equal(identity(move(both, 'right')), '2:2');
    const all = setLayouts(both, [4, 2, 3, 4], 4);
    assert.deepEqual(all, { layouts: [2, 3, 4], columns: 4, column: 2, height, screenWidth: true });
    assert.deepEqual(frame(all), frame(initial));
    assert.equal(identity(move(all, 'left')), '4:2');
    assert.equal(identity(move(all, 'right')), '4:3');
    const removed = setLayouts(all, [2, 3], 4);
    assert.deepEqual(removed, { layouts: [2, 3], columns: 3, column: 2, height, screenWidth: true });
    assert.deepEqual(frame(removed), frame(initial));
    assert.deepEqual(setLayouts(all, [], 4), initial);
    assert.equal(initial.columns, 3);
    assert.deepEqual(initial.layouts, [3]);
  }
});

test('maximized frames fill pixel-aligned bounds and ignore grid and finite nonnegative gap', () => {
  for (const columns of [2, 3, 4]) {
    for (const scale of [1, 2]) {
      for (const gap of [0, 4, 8, 12, 1000, Number.MAX_VALUE]) {
        const dimensions = { width: 901.25, height: 501.75, scale, gap };
        assert.deepEqual(frame(maximize(createState([columns])), dimensions), {
          x: 0, y: 0,
          width: Math.floor(dimensions.width * scale) / scale,
          height: Math.floor(dimensions.height * scale) / scale,
        });
      }
    }
  }
});

test('screen halves span each grid row with matching gaps and pixel-aligned boundaries', () => {
  for (const columns of [2, 3, 4]) {
    for (const scale of [1, 2]) {
      for (const gap of [0, 0.3, 4, 8, 12]) {
        const dimensions = { width: 901.25, height: 501.75, scale, gap };
        const pixelGap = Math.round(gap * scale) / scale;
        const state = maximize(createState([columns]));
        const top = frame(move(state, 'up'), dimensions);
        const bottom = frame(move(state, 'down'), dimensions);
        const topLeft = frame(selectZone(state, 1), dimensions);
        const topRight = frame(selectZone(state, columns), dimensions);
        const bottomLeft = frame(selectZone(state, columns + 1), dimensions);
        const bottomRight = frame(selectZone(state, columns * 2), dimensions);
        assert.deepEqual(top, { ...topLeft, width: topRight.x + topRight.width - topLeft.x });
        assert.deepEqual(bottom, { ...bottomLeft, width: bottomRight.x + bottomRight.width - bottomLeft.x });
        assert.equal(bottom.y - (top.y + top.height), pixelGap);
        assert.ok(Math.abs(top.height - bottom.height) <= 1 / scale);
        for (const rect of [top, bottom]) {
          for (const value of Object.values(rect)) assert.ok(Number.isInteger(value * scale));
          assert.equal(rect.x, pixelGap);
          assert.equal(rect.x + rect.width, Math.floor(dimensions.width * scale) / scale - pixelGap);
          assert.ok(rect.y >= pixelGap);
          assert.ok(rect.y + rect.height <= Math.floor(dimensions.height * scale) / scale - pixelGap);
        }
      }
    }
  }
});

test('screen geometry requires space for one column instead of the preview grid', () => {
  const state = maximize(createState([4]));
  assert.deepEqual(frame(state, { width: 1, height: 1, gap: 8 }), { x: 0, y: 0, width: 1, height: 1 });
  assert.deepEqual(frame(move(state, 'up'), { width: 17, height: 30, gap: 8 }), { x: 8, y: 8, width: 1, height: 3 });
  assert.deepEqual(frame(move(state, 'down'), { width: 17, height: 30, gap: 8 }), { x: 8, y: 19, width: 1, height: 3 });
  for (const height of ['top', 'full', 'bottom']) {
    for (const invalid of [{ width: 0 }, { height: Infinity }, { gap: -1 }, { gap: NaN }, { scale: 0 }, { width: 0.2 }, { width: 2 ** 53 }]) {
      assert.throws(() => frame({ ...state, height }, invalid), RangeError);
    }
  }
  assert.throws(() => frame(move(state, 'up'), { width: 16, height: 30, gap: 8 }), RangeError);
  assert.throws(() => frame(move(state, 'down'), { width: 17, height: 25, gap: 8 }), RangeError);
});
