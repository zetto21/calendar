#ifndef RUNNER_WINDOWS_WIDGETS_H_
#define RUNNER_WINDOWS_WIDGETS_H_
#include <flutter/method_channel.h>
#include <windows.h>
#include <memory>
#include <string>

std::wstring WidgetDirectory();
bool LaunchCalendar(const std::string& mode);
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
RegisterWindowsWidgets(flutter::BinaryMessenger* messenger, HWND window, bool mini);
void RestoreMiniFrame(HWND window, const std::string& mode);
void SaveMiniFrame(HWND window, const std::string& mode);
#endif
