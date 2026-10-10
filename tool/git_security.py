#!/usr/bin/env python3
"""Reject private files and secrets without displaying credential values."""
import argparse
import fnmatch
import hashlib
import io
import os
from pathlib import Path
import platform
import subprocess
import sys
import tarfile
import urllib.request

VERSION = "8.30.1"
# Full history through this commit was reviewed before the guards were added.
# Keep this fixed: new private files must be rejected even if later deleted.
AUDITED_HISTORY = "f107e24a9a39edda2fb6495832d357d196028170"
PRIVATE_PATTERNS = (
    ".env", ".env.*", "*.p8", "*.p12", "*.pfx", "*.key", "*.pem",
    "*.mobileprovision", "*.provisionprofile", "*.jks", "*.keystore",
    "key.properties", "credentials.json", "service-account*.json",
    "*-service-account.json", "*.local.json", "*.local.plist", "*.local.xcconfig",
    "*.ipa", "*.sqlite", "*.sqlite3", "*.db", "calendar-backup*.json",
)
EXAMPLES = {".env.example", ".env.sample", ".env.template"}


def is_private(path):
    parts = Path(path).parts
    name = parts[-1]
    if name in EXAMPLES:
        return False
    return (
        path == ".vscode/settings.json"
        or any(p in {"secrets", "private", "calendar-exports"} for p in parts)
        or any(p.endswith((".xcarchive", ".dSYM")) for p in parts)
        or any(fnmatch.fnmatch(name, pattern) for pattern in PRIVATE_PATTERNS)
    )


def scanner():
    system = {"Darwin": "darwin", "Linux": "linux"}.get(platform.system())
    arch = {"arm64": "arm64", "aarch64": "arm64", "x86_64": "x64", "AMD64": "x64"}.get(platform.machine())
    if not system or not arch:
        raise RuntimeError("Use macOS/Linux for this Git check.")
    directory = Path.home() / ".cache" / "calendar-security" / VERSION
    binary = directory / "gitleaks"
    if binary.exists():
        return binary
    directory.mkdir(parents=True, exist_ok=True)
    name = f"gitleaks_{VERSION}_{system}_{arch}.tar.gz"
    base = f"https://github.com/gitleaks/gitleaks/releases/download/v{VERSION}/"
    with urllib.request.urlopen(base + f"gitleaks_{VERSION}_checksums.txt", timeout=30) as response:
        checksums = response.read().decode()
    expected = next(line.split()[0] for line in checksums.splitlines() if line.split()[-1] == name)
    with urllib.request.urlopen(base + name, timeout=60) as response:
        data = response.read()
    if hashlib.sha256(data).hexdigest() != expected:
        raise RuntimeError("Gitleaks archive checksum mismatch.")
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
        payload = archive.extractfile("gitleaks").read()
    temporary = directory / f"gitleaks-{os.getpid()}.tmp"
    temporary.write_bytes(payload)
    temporary.chmod(0o755)
    temporary.replace(binary)
    return binary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--staged", action="store_true")
    parser.add_argument("--history", action="store_true")
    parser.add_argument("--install", action="store_true")
    args = parser.parse_args()
    root = subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip()
    os.chdir(root)
    if args.install:
        existing = subprocess.run(["git", "config", "--get", "core.hooksPath"], capture_output=True, text=True).stdout.strip()
        if existing and existing != ".githooks":
            raise RuntimeError("Existing hooksPath must be integrated before installation.")
        scanner()
        for name in ("pre-commit", "pre-push"):
            Path(".githooks", name).chmod(0o755)
        subprocess.run(["git", "config", "--local", "core.hooksPath", ".githooks"], check=True)
        print("Installed commit/push secret checks.")
        return 0
    command = ["git", "ls-files", "-z"] if args.staged else ["git", "ls-tree", "-r", "--name-only", "-z", "HEAD"]
    paths = subprocess.check_output(command).decode().split("\0")
    if not args.staged:
        history = [
            "git", "log", "--all", "--format=", "--name-only", "-z",
            "--diff-filter=ACMR",
        ]
        baseline = subprocess.run(["git", "cat-file", "-e", AUDITED_HISTORY + "^{commit}"], capture_output=True)
        if baseline.returncode == 0:
            history += ["--not", AUDITED_HISTORY]
        changed = subprocess.check_output(history).decode().split("\0")
        paths += [path.lstrip("\n") for path in changed]
    blocked = sorted({path for path in paths if path and is_private(path)})
    if blocked:
        for path in blocked:
            print(f"Private file must remain local: {path}", file=sys.stderr)
        print("Use git rm --cached for already tracked private files; local files remain.", file=sys.stderr)
        return 1
    command = [str(scanner()), "git", ".", "--redact=100", "--no-banner"]
    command += ["--staged"] if args.staged else ["--log-opts=--all"]
    # Do not let developer environment settings replace the security rules.
    env = {key: value for key, value in os.environ.items() if not key.startswith("GITLEAKS_")}
    return subprocess.run(command, env=env, stdin=subprocess.DEVNULL).returncode


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print(f"Security check could not finish ({type(error).__name__}); commit/push blocked.", file=sys.stderr)
        sys.exit(2)
