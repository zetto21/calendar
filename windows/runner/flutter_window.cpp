#include "flutter_window.h"

#include <optional>
#include <algorithm>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"
#include "windows_widgets.h"
#include "windows_event_reminders.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  // Consent and login share the same compact, fixed content size as macOS.
  ApplyScreen(false);

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  widget_channel_ = RegisterWindowsWidgets(flutter_controller_->engine()->messenger());
  reminders_channel_ = RegisterWindowsEventReminders(flutter_controller_->engine()->messenger());
  window_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "calendar_app/window",
      &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() != "setScreen") {
          result->NotImplemented();
          return;
        }
        const auto* screen = call.arguments()
            ? std::get_if<std::string>(call.arguments()) : nullptr;
        if (!screen || (*screen != "login" && *screen != "calendar")) {
          result->Error("invalid_screen", "Unknown screen");
          return;
        }
        const bool calendar = *screen == "calendar";
        if (calendar != calendar_screen_) ApplyScreen(calendar);
        result->Success();
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  widget_channel_.reset();
  reminders_channel_.reset();
  window_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::ApplyScreen(bool calendar) {
  const HWND hwnd = GetHandle();
  if (calendar_screen_ && !calendar) {
    WINDOWPLACEMENT placement{sizeof(WINDOWPLACEMENT)};
    GetWindowPlacement(hwnd, &placement);
    calendar_frame_ = placement.rcNormalPosition;
  }
  calendar_screen_ = calendar;
  if (IsZoomed(hwnd)) ShowWindow(hwnd, SW_RESTORE);
  LONG_PTR style = GetWindowLongPtr(hwnd, GWL_STYLE);
  if (calendar) style |= WS_THICKFRAME | WS_MAXIMIZEBOX;
  else style &= ~(WS_THICKFRAME | WS_MAXIMIZEBOX);
  SetWindowLongPtr(hwnd, GWL_STYLE, style);

  MONITORINFO monitor{sizeof(MONITORINFO)};
  GetMonitorInfo(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST), &monitor);
  const RECT work = monitor.rcWork;
  const UINT dpi = GetDpiForWindow(hwnd);
  RECT target{0, 0, MulDiv(calendar ? 1280 : 520, dpi, 96),
                    MulDiv(calendar ? 840 : 720, dpi, 96)};
  AdjustWindowRectExForDpi(&target, static_cast<DWORD>(style), FALSE,
                         static_cast<DWORD>(GetWindowLongPtr(hwnd, GWL_EXSTYLE)), dpi);
  if (calendar && calendar_frame_) target = *calendar_frame_;
  const LONG width = std::min(target.right - target.left, work.right - work.left);
  const LONG height = std::min(target.bottom - target.top, work.bottom - work.top);
  LONG x = work.left + (work.right - work.left - width) / 2;
  LONG y = work.top + (work.bottom - work.top - height) / 2;
  if (calendar && calendar_frame_) {
    x = std::clamp(target.left, work.left, work.right - width);
    y = std::clamp(target.top, work.top, work.bottom - height);
  }
  SetWindowPos(hwnd, nullptr, x, y, width, height,
               SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (!calendar_screen_ && message == WM_SYSCOMMAND &&
      (wparam & 0xfff0) == SC_MAXIMIZE) return 0;
  if (!calendar_screen_ && message == WM_DPICHANGED) {
    Win32Window::MessageHandler(hwnd, message, wparam, lparam);
    ApplyScreen(false);
    return 0;
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
