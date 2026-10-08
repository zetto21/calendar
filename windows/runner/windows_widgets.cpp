#include "windows_widgets.h"
#include <flutter/standard_method_codec.h>
#include <shlobj.h>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <algorithm>

std::wstring WidgetDirectory() {
  PWSTR folder = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &folder)))
    return L"";
  std::wstring path = std::wstring(folder) + L"\\IlsangCalendar\\widgets";
  CoTaskMemFree(folder);
  std::error_code error;
  std::filesystem::create_directories(path, error);
  return error ? L"" : path;
}

bool LaunchCalendar(const std::string& mode) {
  if (!mode.empty() && mode != "today" && mode != "month" && mode != "upcoming") return false;
  const std::wstring title = mode.empty() ? L"일상 캘린더" :
      mode == "month" ? L"일상 캘린더 · 월간 달력" :
      mode == "upcoming" ? L"일상 캘린더 · 다가오는 일정" : L"일상 캘린더 · 오늘 일정";
  if (HWND existing = FindWindow(nullptr, title.c_str())) {
    ShowWindow(existing, SW_RESTORE);
    SetForegroundWindow(existing);
    return true;
  }
  wchar_t executable[32768];
  if (!GetModuleFileName(nullptr, executable, 32768)) return false;
  std::wstring command = L"\"" + std::wstring(executable) + L"\"";
  if (!mode.empty()) command += L" --mini=" + std::wstring(mode.begin(), mode.end());
  STARTUPINFO startup{sizeof(STARTUPINFO)};
  PROCESS_INFORMATION process{};
  auto directory = std::filesystem::path(executable).parent_path().wstring();
  if (!CreateProcess(executable, command.data(), nullptr, nullptr, FALSE, 0,
                     nullptr, directory.c_str(), &startup, &process)) return false;
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  return true;
}

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
RegisterWindowsWidgets(flutter::BinaryMessenger* messenger, HWND window, bool mini) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "calendar_app/home_widget", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([window, mini](const auto& call, auto result) {
    const auto folder = WidgetDirectory();
    if (folder.empty()) { result->Error("widget_storage", "Widget folder unavailable"); return; }
    const auto snapshot = folder + L"\\snapshot.json";
    if (call.method_name() == "update" && !mini) {
      const auto* args = call.arguments() ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
      const std::string* json = nullptr;
      if (args) {
        const auto item = args->find(flutter::EncodableValue("snapshot"));
        if (item != args->end()) json = std::get_if<std::string>(&item->second);
      }
      if (!json || json->size() > 1024 * 1024) { result->Error("invalid_snapshot", "Invalid snapshot"); return; }
      const auto pending = folder + L"\\snapshot." + std::to_wstring(GetCurrentProcessId()) + L".tmp";
      std::ofstream output(std::filesystem::path(pending), std::ios::binary | std::ios::trunc);
      output.write(json->data(), static_cast<std::streamsize>(json->size()));
      output.close();
      if (!output || !MoveFileEx(pending.c_str(), snapshot.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
        DeleteFile(pending.c_str()); result->Error("widget_write", "Could not update snapshot"); return;
      }
      wchar_t executable[32768];
      const DWORD length = GetModuleFileName(nullptr, executable, 32768);
      // UTF-16 matches .NET Encoding.Unicode; no credentials are exported.
      std::ofstream launcher(std::filesystem::path(folder + L"\\launcher.txt"), std::ios::binary | std::ios::trunc);
      launcher.write(reinterpret_cast<const char*>(executable), length * sizeof(wchar_t));
      result->Success();
    } else if (call.method_name() == "read") {
      std::ifstream input(std::filesystem::path(snapshot), std::ios::binary);
      std::ostringstream contents; contents << input.rdbuf();
      const auto json = contents.str();
      result->Success(flutter::EncodableValue(json.size() <= 1024 * 1024 ? json : ""));
    } else if (call.method_name() == "launchMini") {
      const auto* mode = call.arguments() ? std::get_if<std::string>(call.arguments()) : nullptr;
      if (mode && LaunchCalendar(*mode)) result->Success();
      else result->Error("mini_launch", "Could not open mini window");
    } else if (call.method_name() == "openCalendar") {
      if (LaunchCalendar("")) result->Success();
      else result->Error("calendar_launch", "Could not open calendar");
    } else if (call.method_name() == "pin" && mini) {
      const auto* pinned = call.arguments() ? std::get_if<bool>(call.arguments()) : nullptr;
      if (pinned && SetWindowPos(window, *pinned ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0,
                                SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE)) result->Success();
      else result->Error("mini_pin", "Could not pin window");
    } else result->NotImplemented();
  });
  return channel;
}

void RestoreMiniFrame(HWND window, const std::string& mode) {
  HKEY key;
  RECT saved{}; DWORD size = sizeof(saved);
  const auto name = std::wstring(mode.begin(), mode.end());
  bool restored = false;
  if (RegOpenKeyEx(HKEY_CURRENT_USER, L"Software\\IlsangCalendar\\MiniWindows", 0, KEY_READ, &key) == ERROR_SUCCESS) {
    restored = RegQueryValueEx(key, name.c_str(), nullptr, nullptr, reinterpret_cast<BYTE*>(&saved), &size) == ERROR_SUCCESS && size == sizeof(saved);
    RegCloseKey(key);
  }
  MONITORINFO monitor{sizeof(MONITORINFO)};
  GetMonitorInfo(MonitorFromRect(&saved, MONITOR_DEFAULTTONEAREST), &monitor);
  const auto work = monitor.rcWork;
  const auto dpi = GetDpiForWindow(window);
  const LONG width = std::clamp<LONG>(restored ? saved.right - saved.left : MulDiv(380, dpi, 96), std::min<LONG>(MulDiv(320, dpi, 96), work.right - work.left), work.right - work.left);
  const LONG height = std::clamp<LONG>(restored ? saved.bottom - saved.top : MulDiv(mode == "month" ? 560 : 450, dpi, 96), std::min<LONG>(MulDiv(360, dpi, 96), work.bottom - work.top), work.bottom - work.top);
  const LONG x = restored ? std::clamp(saved.left, work.left, work.right - width) : work.right - width - 16;
  const LONG y = restored ? std::clamp(saved.top, work.top, work.bottom - height) : work.top + 24;
  SetWindowPos(window, nullptr, x, y, width, height, SWP_NOZORDER | SWP_NOACTIVATE);
}

void SaveMiniFrame(HWND window, const std::string& mode) {
  if (IsIconic(window)) return;
  WINDOWPLACEMENT placement{sizeof(WINDOWPLACEMENT)};
  if (!GetWindowPlacement(window, &placement)) return;
  HKEY key;
  if (RegCreateKeyEx(HKEY_CURRENT_USER, L"Software\\IlsangCalendar\\MiniWindows", 0, nullptr, 0, KEY_WRITE, nullptr, &key, nullptr) == ERROR_SUCCESS) {
    const auto name = std::wstring(mode.begin(), mode.end());
    RegSetValueEx(key, name.c_str(), 0, REG_BINARY, reinterpret_cast<const BYTE*>(&placement.rcNormalPosition), sizeof(RECT));
    RegCloseKey(key);
  }
}
