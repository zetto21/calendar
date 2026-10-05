import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';

const script = readFileSync(new URL('../web/auth_callback.js', import.meta.url), 'utf8');
const code = 'a'.repeat(43);

function callback(href, { opener = true } = {}) {
  const calls = [];
  const status = { textContent: '' };
  runInNewContext(script, {
    URL,
    document: { getElementById: () => status },
    window: {
      location: { href },
      history: { replaceState: (_, __, path) => calls.push(['scrub', path]) },
      localStorage: { removeItem: (key) => calls.push(['remove', key]) },
      opener: opener ? {
        postMessage: (message, origin) => calls.push(['post', message, origin]),
      } : null,
      close: () => calls.push(['close']),
    },
  });
  return { calls, status };
}

for (const payload of [`code=${code}`, 'error=canceled']) {
  const href = `https://calendar.example/auth.html?${payload}`;
  const { calls } = callback(href);
  assert.deepEqual(calls[0], ['scrub', '/auth.html']);
  assert.equal(calls[2][0], 'post');
  assert.equal(calls[2][1]['flutter-web-auth-2'], href);
  assert.equal(calls[2][2], 'https://calendar.example');
  assert.deepEqual(calls[3], ['close']);
}

for (const href of [
  'https://calendar.example/auth.html?code=short',
  `https://calendar.example/auth.html?code=${code}%0A`,
  `https://calendar.example/auth.html?code=${code}%E2%80%A8`,
  `https://calendar.example/auth.html?code=${code}&code=${code}`,
  `https://calendar.example/auth.html?code=${code}&error=canceled`,
  `https://calendar.example/auth.html?code=${code}&token=secret`,
  `https://calendar.example/other.html?code=${code}`,
  `https://calendar.example/auth.html?code=${code}#other`,
  'https://calendar.example/auth.html?error=bad%0Atext',
]) {
  const { calls, status } = callback(href);
  assert.equal(calls[0][0], 'scrub');
  assert.equal(calls.some(([action]) => action === 'post'), false);
  assert.notEqual(status.textContent, '');
}

assert.equal(
  callback(`https://calendar.example/auth.html?code=${code}`, { opener: false })
    .calls.some(([action]) => action === 'post'),
  false,
);
console.log('web auth callback checks passed');
