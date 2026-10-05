import 'package:web/web.dart' as web;

String? readSession(String key) => web.window.sessionStorage.getItem(key);
void writeSession(String key, String value) =>
    web.window.sessionStorage.setItem(key, value);
void deleteSession(String key) => web.window.sessionStorage.removeItem(key);
// Legacy bearer tokens must not remain readable in persistent local storage.
// Do not migrate them: the user signs in again after this security update.
void deleteLegacySession(String key) {
  // shared_preferences_web prefixes keys with "flutter." by default.
  web.window.localStorage.removeItem('flutter.$key');
  web.window.localStorage.removeItem(key);
}
