#ifndef RUNNER_WINDOWS_EVENT_REMINDERS_H_
#define RUNNER_WINDOWS_EVENT_REMINDERS_H_

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <memory>

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
RegisterWindowsEventReminders(flutter::BinaryMessenger* messenger);
int RunWindowsReminderSmokeTest();

#endif
