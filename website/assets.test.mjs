import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';

const read = path => readFileSync(new URL(path, import.meta.url), 'utf8');

test('changed scripts and styles use content versions to refresh returning visitors', () => {
  for (const [parent, asset] of [
    ['index.html', 'app.mjs'], ['index.html', 'styles.css'],
    ['app.mjs', 'navigation.mjs'], ['app.mjs', 'i18n.mjs']
  ]) {
    const hash = createHash('sha256').update(read(asset)).digest('hex').slice(0, 12);
    assert.ok(read(parent).includes(`./${asset}?v=${hash}`), `${parent} needs the current ${asset} version`);
  }
});
