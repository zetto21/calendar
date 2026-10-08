Based on desktop_webview_window 0.3.0 (MIT license, LICENSE included).

Windows cancels a navigation while awaiting the Dart `onUrlRequested` result.
Return that result from the channel handler and send title bar notifications
without awaiting them, so a secondary engine cannot block navigation approval.

Allow Windows HTTP(S) navigation to continue while notifying Dart. Keep the
decision handler for custom-scheme redirects, including calendar://auth.
Consequently the Windows URL callback observes HTTP(S) requests; it cannot veto
them. Calendar authentication validates the callback before exchanging a code.

Complete the close future after a programmatic close as well as an OS close
event. Completion is idempotent because either path can notify first.

Upstream: https://github.com/MixinNetwork/flutter-plugins/tree/main/packages/desktop_webview_window
