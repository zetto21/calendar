#ifndef RUNNER_WINDOWS_WIDGETS_H_
#define RUNNER_WINDOWS_WIDGETS_H_
#include <flutter/method_channel.h>
#include <memory>

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
RegisterWindowsWidgets(flutter::BinaryMessenger* messenger);
#endif
