Based on desktop_webview_window 0.3.0 (MIT license, LICENSE included).

Windows cancels a navigation while awaiting the Dart `onUrlRequested` result.
Return that result from the channel handler and send title bar notifications
without awaiting them, so a secondary engine cannot block navigation approval.

Allow Windows HTTP(S) navigation to continue while notifying Dart. Cancel
custom-scheme redirects, including calendar://auth, and notify Dart without
an asynchronous reply callback capturing the WebView's `this` or `sender`.
Authentication closes the view during that callback, so these pointers would
be freed before a reply arrives (Windows access violation at web_view.cc:210).
Consequently the Windows URL callback observes HTTP(S) requests; it cannot veto
them. Calendar authentication validates the callback before exchanging a code.

Complete the close future after a programmatic close as well as an OS close
event. Completion is idempotent because either path can notify first.

Upstream: https://github.com/MixinNetwork/flutter-plugins/tree/main/packages/desktop_webview_window
