#include "windows_event_reminders.h"

#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <appmodel.h>
#include <shlobj.h>
#include <propsys.h>
#include <propkey.h>
#include <propvarutil.h>
#include <wrl/client.h>
#include <winrt/Windows.Data.Xml.Dom.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.UI.Notifications.h>

#include <chrono>
#include <filesystem>
#include <fstream>
#include <map>
#include <set>
#include <string>
#include <vector>

namespace {
using namespace winrt::Windows::UI::Notifications;
constexpr wchar_t kAppId[] = L"IlsangCalendar.Calendar.Windows";
constexpr wchar_t kGroup[] = L"reminders";
std::wstring app_id = kAppId;

void EnsureIdentity() {
  static bool registered = false;
  if (registered) return;
  static bool initialized = false;
  if (!initialized) {
    winrt::init_apartment(winrt::apartment_type::single_threaded);
    initialized = true;
  }
  UINT32 identity_length = 0;
  if (GetCurrentApplicationUserModelId(&identity_length, nullptr) == ERROR_INSUFFICIENT_BUFFER) {
    std::vector<wchar_t> identity(identity_length);
    if (GetCurrentApplicationUserModelId(&identity_length, identity.data()) == ERROR_SUCCESS) {
      app_id = identity.data();
      registered = true;
      return;
    }
  }
  winrt::check_hresult(SetCurrentProcessExplicitAppUserModelID(kAppId));
  PWSTR programs = nullptr;
  winrt::check_hresult(SHGetKnownFolderPath(FOLDERID_Programs, 0, nullptr, &programs));
  std::wstring shortcut = std::wstring(programs) + L"\\일상 캘린더.lnk";
  CoTaskMemFree(programs);
  wchar_t executable[32768];
  const auto length = GetModuleFileNameW(nullptr, executable, 32768);
  if (!length || length >= 32768) throw winrt::hresult_error(E_FAIL);
  Microsoft::WRL::ComPtr<IShellLinkW> link;
  winrt::check_hresult(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                                        IID_PPV_ARGS(&link)));
  winrt::check_hresult(link->SetPath(executable));
  winrt::check_hresult(link->SetIconLocation(executable, 0));
  const std::wstring path(executable);
  winrt::check_hresult(link->SetWorkingDirectory(path.substr(0, path.find_last_of(L"\\/")).c_str()));
  Microsoft::WRL::ComPtr<IPropertyStore> properties;
  winrt::check_hresult(link.As(&properties));
  PROPVARIANT identity;
  winrt::check_hresult(InitPropVariantFromString(kAppId, &identity));
  const HRESULT assigned = properties->SetValue(PKEY_AppUserModel_ID, identity);
  PropVariantClear(&identity);
  winrt::check_hresult(assigned);
  winrt::check_hresult(properties->Commit());
  Microsoft::WRL::ComPtr<IPersistFile> file;
  winrt::check_hresult(link.As(&file));
  winrt::check_hresult(file->Save(shortcut.c_str(), TRUE));
  registered = true;
}

std::string Text(const flutter::EncodableMap& values, const char* key) {
  const auto found = values.find(flutter::EncodableValue(key));
  if (found == values.end()) throw winrt::hresult_invalid_argument();
  const auto value = std::get_if<std::string>(&found->second);
  if (!value) throw winrt::hresult_invalid_argument();
  return *value;
}

int64_t Integer(const flutter::EncodableMap& values, const char* key) {
  const auto found = values.find(flutter::EncodableValue(key));
  if (found == values.end()) throw winrt::hresult_invalid_argument();
  if (const auto value = std::get_if<int64_t>(&found->second)) return *value;
  if (const auto value = std::get_if<int32_t>(&found->second)) return *value;
  throw winrt::hresult_invalid_argument();
}

std::wstring Escape(const std::string& text) {
  const auto wide = winrt::to_hstring(text);
  std::wstring result;
  for (const auto letter : wide) {
    switch (letter) {
      case L'&': result += L"&amp;"; break;
      case L'<': result += L"&lt;"; break;
      case L'>': result += L"&gt;"; break;
      case L'\"': result += L"&quot;"; break;
      case L'\'': result += L"&apos;"; break;
      default: if (letter >= 32 || letter == L'\n' || letter == L'\t') result += letter;
    }
  }
  return result;
}

winrt::Windows::Data::Xml::Dom::XmlDocument Content(const std::string& title,
                                                   const std::string& body) {
  winrt::Windows::Data::Xml::Dom::XmlDocument document;
  document.LoadXml(L"<toast scenario=\"reminder\"><visual><binding template=\"ToastGeneric\">"
      L"<text>" + Escape(title) + L"</text><text>" + Escape(body) +
      L"</text></binding></visual><actions>"
      L"<input id=\"snoozeTime\" type=\"selection\" defaultInput=\"5\">"
      L"<selection id=\"5\" content=\"5분\"/></input>"
      L"<action activationType=\"system\" arguments=\"snooze\" hint-inputId=\"snoozeTime\" content=\"다시 알림\"/>"
      L"<action activationType=\"system\" arguments=\"dismiss\" content=\"닫기\"/>"
      L"</actions></toast>");
  return document;
}

winrt::Windows::Foundation::DateTime Timestamp(int64_t millis) {
  return winrt::clock::from_sys(std::chrono::system_clock::time_point(std::chrono::milliseconds(millis)));
}

struct Reminder {
  winrt::hstring id;
  winrt::Windows::Data::Xml::Dom::XmlDocument content;
  winrt::Windows::Foundation::DateTime at, expires;
};

void Schedule(const flutter::EncodableValue* arguments) {
  const auto values = arguments ? std::get_if<flutter::EncodableList>(arguments) : nullptr;
  if (!values || values->size() > 256) throw winrt::hresult_invalid_argument();
  std::map<std::wstring, Reminder> desired;
  for (const auto& raw : *values) {
    const auto item = std::get_if<flutter::EncodableMap>(&raw);
    if (!item) throw winrt::hresult_invalid_argument();
    const auto id = Text(*item, "id");
    const auto title = Text(*item, "title"), body = Text(*item, "body");
    if (id.size() != 16 || id.find_first_not_of("0123456789abcdef") != std::string::npos ||
        title.size() > 1024 || body.size() > 2048) throw winrt::hresult_invalid_argument();
    const auto at = Timestamp(Integer(*item, "at"));
    const auto expires = Timestamp(Integer(*item, "expires"));
    if (expires <= at) throw winrt::hresult_invalid_argument();
    const auto wideId = winrt::to_hstring(id);
    desired.emplace(std::wstring(wideId), Reminder{wideId, Content(title, body), at, expires});
  }
  EnsureIdentity();
  const auto notifier = ToastNotificationManager::CreateToastNotifier(app_id);
  const auto now = winrt::clock::now();
  std::set<std::wstring> retained;
  const auto scheduled = notifier.GetScheduledToastNotifications();
  std::vector<ScheduledToastNotification> existing(scheduled.begin(), scheduled.end());
  for (const auto& notification : existing) {
    if (notification.Group() != kGroup) continue;
    const auto id = std::wstring(notification.Tag());
    const auto found = desired.find(id);
    if (found != desired.end() && found->second.expires > now &&
        (found->second.at <= now || (notification.DeliveryTime() == found->second.at &&
         notification.Content().GetXml() == found->second.content.GetXml()))) {
      retained.insert(id);
    } else {
      notifier.RemoveFromSchedule(notification);
    }
  }
  for (const auto& entry : desired) {
    const auto& reminder = entry.second;
    if (retained.count(entry.first) || reminder.at <= now || reminder.expires <= now) continue;
    ScheduledToastNotification notification(reminder.content, reminder.at);
    // This Windows build rejects 16 characters for Id (the null counts too).
    // Keep the full hash in Tag, which supports all 16 characters.
    notification.Id(std::wstring(reminder.id).substr(0, 15));
    notification.Tag(reminder.id);
    notification.Group(kGroup);
    notification.ExpirationTime(reminder.expires);
    notifier.AddToSchedule(notification);
  }
  const auto history = ToastNotificationManager::History();
  for (const auto& notification : history.GetHistory(app_id)) {
    if (notification.Group() == kGroup && !desired.count(std::wstring(notification.Tag())))
      history.Remove(notification.Tag(), kGroup, app_id);
  }
}

void Clear() {
  EnsureIdentity();
  const auto notifier = ToastNotificationManager::CreateToastNotifier(app_id);
  const auto scheduled = notifier.GetScheduledToastNotifications();
  std::vector<ScheduledToastNotification> existing(scheduled.begin(), scheduled.end());
  for (const auto& notification : existing)
    if (notification.Group() == kGroup) notifier.RemoveFromSchedule(notification);
  ToastNotificationManager::History().Clear(app_id);
}
}  // namespace

int RunWindowsReminderSmokeTest() {
  auto log = [](const std::string& message) {
    PWSTR local = nullptr;
    if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &local))) {
      const auto directory = std::filesystem::path(local) / L"IlsangCalendar" / L"widgets";
      CoTaskMemFree(local);
      std::filesystem::create_directories(directory);
      std::ofstream(directory / L"reminder-smoke-test.txt") << message;
    }
  };
  std::string stage = "create schedule";
  try {
    const auto now = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();
    flutter::EncodableMap reminder{
      {flutter::EncodableValue("id"), flutter::EncodableValue("0123456789abcdef")},
      {flutter::EncodableValue("title"), flutter::EncodableValue("일정 <테스트> & 확인")},
      {flutter::EncodableValue("body"), flutter::EncodableValue("예약 수정과 삭제 확인")},
      {flutter::EncodableValue("at"), flutter::EncodableValue(static_cast<int64_t>(now + 120000))},
      {flutter::EncodableValue("expires"), flutter::EncodableValue(static_cast<int64_t>(now + 600000))},
    };
    auto value = flutter::EncodableValue(flutter::EncodableList{flutter::EncodableValue(reminder)});
    Schedule(&value);
    stage = "read schedule";
    auto notifier = ToastNotificationManager::CreateToastNotifier(app_id);
    if (notifier.GetScheduledToastNotifications().Size() != 1) return 2;
    Schedule(&value);  // Identical updates must not duplicate the reminder.
    if (notifier.GetScheduledToastNotifications().Size() != 1) return 3;
    reminder[flutter::EncodableValue("at")] = flutter::EncodableValue(static_cast<int64_t>(now + 180000));
    value = flutter::EncodableValue(flutter::EncodableList{flutter::EncodableValue(reminder)});
    Schedule(&value);
    auto updated = notifier.GetScheduledToastNotifications();
    if (updated.Size() != 1 || updated.GetAt(0).DeliveryTime() != Timestamp(now + 180000)) return 4;
    value = flutter::EncodableValue(flutter::EncodableList{});
    Schedule(&value);
    if (notifier.GetScheduledToastNotifications().Size() != 0) return 5;
    Clear();
    log("WINDOWS_REMINDERS_PASS");
    return 0;
  } catch (const winrt::hresult_error& error) {
    OutputDebugStringW(error.message().c_str());
    log(stage + ": " + std::to_string(error.code().value) + " " + winrt::to_string(error.message()));
    try { Clear(); } catch (...) {}
    return 1;
  }
}

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
RegisterWindowsEventReminders(flutter::BinaryMessenger* messenger) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "calendar/windows_event_reminders", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([](const auto& call, auto result) {
    try {
      if (call.method_name() == "schedule") Schedule(call.arguments());
      else if (call.method_name() == "clear") Clear();
      else if (call.method_name() == "test") {
        EnsureIdentity();
        ToastNotification test(Content("일상 캘린더 · 알림 테스트", "일정 시작 10분 전에 이 알림이 표시됩니다."));
        test.Tag(L"reminder-test");
        test.Group(kGroup);
        ToastNotificationManager::CreateToastNotifier(app_id).Show(test);
      } else { result->NotImplemented(); return; }
      result->Success();
    } catch (const winrt::hresult_error& error) {
      result->Error("windows_reminder_error", winrt::to_string(error.message()));
    } catch (const std::exception&) {
      result->Error("windows_reminder_error", "알림을 예약하지 못했습니다.");
    }
  });
  return channel;
}
