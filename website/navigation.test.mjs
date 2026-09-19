import test from 'node:test';
import assert from 'node:assert/strict';
import { candidates, createState, move, selectZone, setLayouts, selectedZones, frame } from './navigation.mjs';

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
      let state = { layouts, columns: first.columns, column: first.column, height };
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
  assert.deepEqual(createState([2]), { layouts: [2], columns: 2, column: 1, height: 'full' });
  assert.deepEqual(createState([4]), { layouts: [4], columns: 4, column: 2, height: 'full' });
  assert.deepEqual(createState([2, 3, 4]), { layouts: [2, 3, 4], columns: 3, column: 2, height: 'full' });
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
  assert.deepEqual(next, { layouts: [3], columns: 3, column: 3, height: 'bottom' });
  const centered = selectZone(createState([3]), 2);
  assert.deepEqual(setLayouts(centered, [2]), { layouts: [2], columns: 2, column: 1, height: 'top' });
  assert.deepEqual(setLayouts(centered, []), centered);
  assert.deepEqual(setLayouts(centered, [3, 2, 3]).layouts, [2, 3]);
});

test('navigation returns new state without changing previous selection', () => {
  const initial = Object.freeze({ layouts: Object.freeze([2, 3]), columns: 3, column: 2, height: 'full' });
  const right = move(initial, 'right');
  const upper = move(initial, 'up');
  assert.equal(identity(right), '2:2');
  assert.equal(upper.height, 'top');
  assert.deepEqual(initial, { layouts: [2, 3], columns: 3, column: 2, height: 'full' });
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
