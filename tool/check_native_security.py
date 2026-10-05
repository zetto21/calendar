#!/usr/bin/env python3
"""Check native security policies and production Swift boundary functions.

Run on macOS with the Xcode Swift toolchain:
    python3 tool/check_native_security.py

Swift functions are extracted from the current production source. The Keychain
probe replaces SecItem functions with an in-memory mock; it never reads or
writes the user's Keychain. File probes use their own synthetic temporary data.
"""

from pathlib import Path
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
ANDROID = "{http://schemas.android.com/apk/res/android}"


def section(source: str, start: str, end: str) -> str:
    beginning = source.index(start)
    return source[beginning:source.index(end, beginning)]


def check_android_policies() -> None:
    manifest = ET.parse(ROOT / "android/app/src/main/AndroidManifest.xml")
    app = manifest.getroot().find("application")
    assert app is not None
    assert app.get(ANDROID + "allowBackup") == "false", "Automatic backup must be disabled"
    assert app.get(ANDROID + "fullBackupContent") == "false", "Legacy backup must be disabled"
    assert app.get(ANDROID + "usesCleartextTraffic") == "false", "Release HTTP must be disabled"
    assert app.get(ANDROID + "networkSecurityConfig") is None, "Debug HTTP policy must not be in release"
    assert app.get(ANDROID + "dataExtractionRules") == "@xml/data_extraction_rules"
    rules = ET.parse(ROOT / "android/app/src/main/res/xml/data_extraction_rules.xml").getroot()
    domains = {"root", "file", "database", "sharedpref", "external", "device_root",
               "device_file", "device_database", "device_sharedpref"}
    for mode in ("cloud-backup", "device-transfer"):
        node = rules.find(mode)
        assert node is not None, f"Missing {mode} exclusion policy"
        excluded = {entry.get("domain") for entry in node.findall("exclude") if entry.get("path") == "."}
        assert domains <= excluded, f"Private storage must be excluded from {mode}"
    debug = ET.parse(ROOT / "android/app/src/debug/res/xml/network_security_config.xml").getroot()
    base = debug.find("base-config")
    assert base is not None and base.get("cleartextTrafficPermitted") == "false"
    allowed_hosts = set()
    for node in debug.findall("domain-config"):
        if node.get("cleartextTrafficPermitted") == "true":
            for domain in node.findall("domain"):
                assert domain.get("includeSubdomains") == "false"
                allowed_hosts.add(domain.text)
    assert allowed_hosts == {"10.0.2.2", "localhost", "127.0.0.1", "[::1]"}, "Debug HTTP must remain local"
    callbacks = [activity for activity in app.findall("activity")
                 if activity.get(ANDROID + "name") == "com.linusu.flutter_web_auth_2.CallbackActivity"]
    assert len(callbacks) == 1
    callback = callbacks[0].find("intent-filter/data")
    assert callback is not None
    assert callback.get(ANDROID + "scheme") == "calendar" and callback.get(ANDROID + "host") == "auth"
    for node in app.findall("service") + app.findall("receiver"):
        assert node.get(ANDROID + "exported") == "false", "Internal live-update components must remain private"
    signing = (ROOT / "android/app/build.gradle.kts").read_text()
    assert 'signingConfigs.getByName("debug")' not in signing, "Release must not fall back to the debug key"
    print("Android backup, network, callback and signing policy checks passed", flush=True)


def swift_probes() -> dict[str, tuple[str, str]]:
    export = (ROOT / "ios/Runner/AppDelegate.swift").read_text()
    export_method = section(export, "  private static func validatedBackupURL(",
                            "\n  func documentPickerWasCancelled")
    export_method = export_method.replace("  private static func", "func", 1)

    event = (ROOT / "ios/Runner/EventKitChannel.swift").read_text()
    properties = section(event, "  private let isoFormatter:", "\n  static func register")
    parser = section(event, "  private func parseISO(", "\n  private func handle(")
    times = section(event, "  private func eventTimes(", "\n  private func applyRecurrence(")
    event_class = "final class EventTimesHarness {\n" + properties + "\n" + parser + "\n" + times + "\n}\n"
    event_class = event_class.replace("private func", "func")

    session = (ROOT / "macos/Runner/MainFlutterWindow.swift").read_text()
    handler_start = "    sessionChannel?.setMethodCallHandler { call, result in"
    handler = section(session, handler_start, "\n    // Start compact,")
    handler = handler[len(handler_start):].rsplit("\n    }", 1)[0]
    protected_writer = section(session, "  private static func saveProtectedSession(",
                               '\n\n\n  /// Invoked')
    session_class = ("final class SessionHarness {\n"
                     "  func handle(_ call: MockCall, result: (Any?) -> Void) {\n" + handler
                     + "\n  }\n" + protected_writer + "\n}\n")
    return {
        "export_path_checks": ("{{VALIDATED_BACKUP_URL}}", export_method),
        "event_time_checks": ("{{EVENT_TIME_CLASS}}", event_class),
        "keychain_session_checks": ("{{SESSION_HANDLER_CLASS}}", session_class),
    }


def main() -> None:
    check_android_policies()
    swift = shutil.which("swift")
    if swift is None:
        raise SystemExit("The Swift boundary probes require macOS and the Xcode Swift toolchain.")
    with tempfile.TemporaryDirectory(prefix="calendar-native-security-") as directory:
        for name, (placeholder, production_code) in swift_probes().items():
            template = (ROOT / "test/native" / (name + ".swift.template")).read_text()
            assert template.count(placeholder) == 1, f"Invalid {name} template"
            probe = Path(directory) / (name + ".swift")
            probe.write_text(template.replace(placeholder, production_code))
            subprocess.run([swift, str(probe)], cwd=ROOT, check=True)


if __name__ == "__main__":
    main()
