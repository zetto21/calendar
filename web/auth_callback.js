(() => {
  const callback = new URL(window.location.href);
  // Remove credentials from browser history before loading anything else or
  // sending the callback to the app. The callback document has no resources
  // other than this same-origin script and never uses persistent storage.
  window.history.replaceState(null, '', callback.pathname);
  try {
    // Remove records left by versions that used the plugin's storage fallback.
    window.localStorage.removeItem('flutter-web-auth-2');
  } catch (_) {
    // Storage may be disabled; authentication does not depend on it.
  }

  const parameters = callback.searchParams;
  const allowed = new Set(['code', 'error']);
  const keys = [...parameters.keys()];
  const code = parameters.get('code');
  const error = parameters.get('error');
  const validCode = code !== null && code.length === 43 &&
    /^[A-Za-z0-9_-]{43}$/.test(code);
  const validError = error !== null && error.length > 0 &&
    error.length <= 512 && !/[\x00-\x1f\x7f]/.test(error);
  const valid = callback.pathname === '/auth.html' &&
    callback.hash === '' && callback.href.length <= 4096 &&
    callback.username === '' && callback.password === '' &&
    keys.every((key) => allowed.has(key) && parameters.getAll(key).length === 1) &&
    ((validCode && error === null) || (validError && code === null));

  if (!valid || !window.opener) {
    document.getElementById('status').textContent =
      '로그인 창이 만료되었거나 인증 응답을 확인하지 못했습니다. 앱에서 다시 로그인해 주세요.';
    return;
  }
  window.opener.postMessage(
    { 'flutter-web-auth-2': callback.href },
    callback.origin,
  );
  window.close();
})();
