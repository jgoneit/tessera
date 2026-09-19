import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { messages, resolveLanguage, t, translateDocument } from './i18n.mjs';

const placeholders = text => [...text.matchAll(/\{(\w+)\}/g)].map(match => match[1]).sort();

test('Korean and English cover the same nonempty messages and interpolation values', () => {
  assert.deepEqual(Object.keys(messages).sort(), ['en', 'ko']);
  assert.deepEqual(Object.keys(messages.en).sort(), Object.keys(messages.ko).sort());
  for (const key of Object.keys(messages.ko)) {
    for (const language of ['ko', 'en']) {
      assert.equal(typeof messages[language][key], 'string', `${language}: ${key}`);
      assert.ok(messages[language][key].trim(), `${language}: ${key}`);
    }
    assert.deepEqual(placeholders(messages.en[key]), placeholders(messages.ko[key]), key);
  }
});

test('explicit URL language wins over saved and browser languages', () => {
  assert.equal(resolveLanguage({ requested: 'ko', saved: 'en', preferred: ['en-US'] }), 'ko');
  assert.equal(resolveLanguage({ requested: 'en', saved: 'ko', preferred: ['ko-KR'] }), 'en');
});

test('saved language wins when the URL language is absent or unsupported', () => {
  for (const requested of [undefined, null, '', 'de', 'en-US', 'constructor', '__proto__']) {
    assert.equal(resolveLanguage({ requested, saved: 'ko', preferred: ['en-US'] }), 'ko');
    assert.equal(resolveLanguage({ requested, saved: 'en', preferred: ['ko-KR'] }), 'en');
  }
});

test('first supported browser language is normalized and otherwise falls back to English', () => {
  assert.equal(resolveLanguage({ requested: 'fr', saved: 'de', preferred: ['fr-FR', 'KO-kr', 'en-US'] }), 'ko');
  assert.equal(resolveLanguage({ preferred: ['de-DE', 'en-GB', 'ko-KR'] }), 'en');
  assert.equal(resolveLanguage({ preferred: [null, undefined, 77, {}, 'ko'] }), 'ko');
  for (const options of [{}, { preferred: [] }, { requested: null, saved: 'invalid', preferred: ['ja-JP', 'fr'] }]) {
    assert.equal(resolveLanguage(options), 'en');
  }
  assert.equal(resolveLanguage(), 'en');
});

test('selection and cell labels distinguish each grid, column, and height in both languages', () => {
  const heights = {
    ko: { top: '위칸', full: '열 전체', bottom: '아래칸' },
    en: { top: 'Top', full: 'Full column', bottom: 'Bottom' }
  };
  for (const language of ['ko', 'en']) {
    for (const columns of [2, 3, 4]) {
      assert.equal(t(language, 'grid.label', { columns }), language === 'ko'
        ? `${columns}×2 격자 영역 선택`
        : `Choose a cell in the ${columns}×2 grid`);
      for (let column = 1; column <= columns; column += 1) {
        for (const height of ['top', 'full', 'bottom']) {
          const heightName = t(language, `height.${height}`);
          assert.equal(heightName, heights[language][height]);
          assert.equal(t(language, 'selection', { columns, column, height: heightName }), language === 'ko'
            ? `${columns}×2 · ${column}열 · ${heightName}`
            : `${columns}×2 · Column ${column} · ${heightName}`);
          if (height === 'full') continue;
          const id = column + (height === 'bottom' ? columns : 0);
          assert.equal(t(language, 'zone.label', { id, column, height: heightName }), language === 'ko'
            ? `${id}번 영역, ${column}열 ${heightName}`
            : `Cell ${id}, column ${column}, ${heightName}`);
        }
      }
    }
  }
});

test('unknown messages and incomplete interpolation fail instead of displaying broken copy', () => {
  for (const language of ['ko', 'en']) {
    assert.throws(() => t(language, 'missing.message'), /Unknown translation: missing\.message/);
    assert.throws(() => t(language, 'selection', { columns: 3, column: 2 }), /Missing translation value: height/);
    assert.throws(() => t(language, 'grid.label'), /Missing translation value: columns/);
  }
  assert.equal(t('unsupported', 'height.full'), 'Full column');
});

test('screen-wide labels are independent of the preview grid in both languages', () => {
  const labels = {
    ko: { label: '화면 전체 너비', top: '화면 위쪽 절반', full: '최대화', bottom: '화면 아래쪽 절반' },
    en: { label: 'Full screen width', top: 'Top half of screen', full: 'Maximized', bottom: 'Bottom half of screen' }
  };
  for (const language of ['ko', 'en']) {
    for (const [state, expected] of Object.entries(labels[language])) {
      assert.equal(t(language, `screen.${state}`), expected);
      assert.deepEqual(placeholders(messages[language][`screen.${state}`]), []);
      assert.doesNotMatch(t(language, `screen.${state}`), /[234]×2|Column|열 ·/);
    }
    assert.equal(t(language, 'action.maximize'), language === 'ko' ? '최대화' : 'Maximize');
    assert.equal(t(language, 'usage.maximizeKeys'), 'Control Option Return');
  }
});

test('every HTML translation binding resolves without interpolation in either language', () => {
  const html = readFileSync(new URL('./index.html', import.meta.url), 'utf8');
  const bindings = [...html.matchAll(/\b(data-i18n(?:-aria-label|-title)?)="([^"]+)"/g)];
  assert.ok(bindings.length > 0, 'HTML must expose translation bindings');
  assert.deepEqual([...new Set(bindings.map(match => match[1]))].sort(), ['data-i18n', 'data-i18n-aria-label', 'data-i18n-title']);
  for (const [, attribute, key] of bindings) {
    for (const language of ['ko', 'en']) {
      assert.ok(Object.hasOwn(messages[language], key), `${attribute}: ${language}.${key}`);
      assert.doesNotThrow(() => t(language, key), `${attribute}: ${language}.${key}`);
    }
  }
});

test('switching document language updates visible copy, accessible names, and metadata both ways', () => {
  const element = attributes => ({
    attributes: { ...attributes },
    dataset: { i18n: attributes['data-i18n'] },
    textContent: '',
    getAttribute(name) { return this.attributes[name]; },
    setAttribute(name, value) { this.attributes[name] = value; }
  });
  const heading = element({ 'data-i18n': 'hero.title1' });
  const button = element({ 'data-i18n-aria-label': 'direction.left', 'data-i18n-title': 'theme.title' });
  const maximizeButton = element({ 'data-i18n': 'action.maximize', 'data-i18n-aria-label': 'action.maximizeLabel' });
  const screenStates = ['top', 'full', 'bottom'].map(state => element({ 'data-i18n': `screen.${state}` }));
  const metadata = new Map([
    ['meta[name="description"]', element({})],
    ['meta[property="og:title"]', element({})],
    ['meta[property="og:description"]', element({})]
  ]);
  const document = {
    documentElement: { lang: 'ko' },
    title: '',
    querySelector(selector) { return metadata.get(selector); },
    querySelectorAll(selector) {
      return [heading, button, maximizeButton, ...screenStates].filter(node => Object.hasOwn(node.attributes, selector.slice(1, -1)));
    }
  };
  for (const language of ['en', 'ko']) {
    translateDocument(document, language);
    assert.equal(document.documentElement.lang, language);
    assert.equal(document.title, messages[language]['meta.title']);
    assert.equal(heading.textContent, messages[language]['hero.title1']);
    assert.equal(button.getAttribute('aria-label'), messages[language]['direction.left']);
    assert.equal(button.getAttribute('title'), messages[language]['theme.title']);
    assert.equal(maximizeButton.textContent, messages[language]['action.maximize']);
    assert.equal(maximizeButton.getAttribute('aria-label'), messages[language]['action.maximizeLabel']);
    for (const state of screenStates) {
      assert.equal(state.textContent, messages[language][state.dataset.i18n]);
    }
    assert.equal(metadata.get('meta[name="description"]').getAttribute('content'), messages[language]['meta.description']);
    assert.equal(metadata.get('meta[property="og:title"]').getAttribute('content'), document.title);
    assert.equal(metadata.get('meta[property="og:description"]').getAttribute('content'), messages[language]['meta.socialDescription']);
  }
});
