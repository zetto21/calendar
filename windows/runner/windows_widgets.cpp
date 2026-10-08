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

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
RegisterWindowsWidgets(flutter::BinaryMessenger* messenger) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "calendar_app/home_widget", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([](const auto& call, auto result) {
    const auto folder = WidgetDirectory();
    if (folder.empty()) { result->Error("widget_storage", "Widget folder unavailable"); return; }
    const auto snapshot = folder + L"\\snapshot.json";
    if (call.method_name() == "update") {
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
    } else result->NotImplemented();
  });
  return channel;
}
