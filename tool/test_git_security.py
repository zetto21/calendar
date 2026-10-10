#!/usr/bin/env python3
"""Exercise the Git privacy guard without changing the application repository."""
import os
from pathlib import Path
import shutil
import string
import subprocess
import tempfile
import unittest
from random import SystemRandom


SOURCE = Path(__file__).resolve().parents[1]


class GitSecurityTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="calendar-git-guard-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name) / "work"
        self.root.mkdir()
        (self.root / "tool").mkdir()
        shutil.copy2(SOURCE / "tool/git_security.py", self.root / "tool/git_security.py")
        shutil.copytree(SOURCE / ".githooks", self.root / ".githooks")
        self.run_git("init", "-q")
        self.run_git("config", "user.name", "Security test")
        self.run_git("config", "user.email", "security-test@example.invalid")
        (self.root / "README.md").write_text("Isolated security guard test.\n")
        self.run_git("add", "README.md")
        self.commit_without_hooks()

    def run_git(self, *arguments):
        result = subprocess.run(
            ["git", *arguments], cwd=self.root, capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, "Isolated Git setup failed")
        return result

    def commit_without_hooks(self):
        self.run_git("-c", "core.hooksPath=/dev/null", "commit", "-qm", "Test fixture")

    def stage(self, path, content):
        file = self.root / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(content)
        self.run_git("add", "-f", "--", path)

    def guard(self, mode, extra_environment=None):
        environment = os.environ.copy()
        environment.update(extra_environment or {})
        return subprocess.run(
            ["python3", "tool/git_security.py", mode], cwd=self.root,
            capture_output=True, text=True, env=environment,
        )

    def install_hooks(self):
        result = self.guard("--install")
        self.assertEqual(result.returncode, 0, "Hook installation failed")
        self.assertEqual(self.run_git("config", "--local", "core.hooksPath").stdout.strip(), ".githooks")

    def synthetic_credential(self):
        random = SystemRandom()
        alphabet = string.ascii_letters + string.digits
        return "ghp_" + "".join(random.choice(alphabet) for _ in range(36))

    def assert_blocked_without_exposure(self, result, credential=None):
        self.assertNotEqual(result.returncode, 0, "Unsafe change unexpectedly passed")
        if credential:
            self.assertTrue(
                credential not in result.stdout + result.stderr,
                "Scanner exposed a synthetic credential",
            )

    def test_public_source_and_environment_example_are_allowed(self):
        self.stage("lib/public.dart", "const endpoint = 'https://example.invalid';\n")
        self.stage(".env.example", "API_BASE_URL=https://example.invalid\n")
        self.assertEqual(self.guard("--staged").returncode, 0, "Public configuration was blocked")
        self.commit_without_hooks()
        self.assertEqual(self.guard("--history").returncode, 0, "Public history was blocked")

    def test_private_files_are_blocked_even_when_force_added(self):
        for path in (".env", "credentials.json", "signing/AuthKey.p8", ".vscode/settings.json"):
            with self.subTest(path=path):
                self.stage(path, "local-only data\n")
                self.assert_blocked_without_exposure(self.guard("--staged"))
                self.run_git("reset", "-q", "HEAD", "--", path)

    def test_real_pre_commit_hook_blocks_a_secret_and_redacts_output(self):
        self.install_hooks()
        credential = self.synthetic_credential()
        self.stage("lib/auth_fixture.dart", f"const token = '{credential}';\n")
        result = subprocess.run(
            ["git", "commit", "-qm", "Should be blocked"], cwd=self.root,
            capture_output=True, text=True,
        )
        self.assert_blocked_without_exposure(result, credential)
        self.assertEqual(self.run_git("rev-list", "--count", "HEAD").stdout.strip(), "1")

    def test_real_pre_push_hook_blocks_historical_secret_and_redacts_output(self):
        self.install_hooks()
        credential = self.synthetic_credential()
        self.stage("lib/auth_fixture.dart", f"const token = '{credential}';\n")
        self.commit_without_hooks()
        self.run_git("rm", "lib/auth_fixture.dart")
        self.commit_without_hooks()
        remote = Path(self.directory.name) / "remote.git"
        subprocess.run(["git", "init", "--bare", "-q", str(remote)], check=True)
        self.run_git("remote", "add", "origin", str(remote))
        result = subprocess.run(
            ["git", "push", "origin", "HEAD:refs/heads/test"], cwd=self.root,
            capture_output=True, text=True,
        )
        self.assert_blocked_without_exposure(result, credential)
        references = subprocess.run(
            ["git", "--git-dir", str(remote), "for-each-ref"],
            capture_output=True, text=True, check=True,
        )
        self.assertEqual(references.stdout, "", "Blocked push modified the remote")

    def test_environment_cannot_disable_secret_rules(self):
        credential = self.synthetic_credential()
        self.stage("lib/auth_fixture.dart", f"const token = '{credential}';\n")
        result = self.guard("--staged", {
            "GITLEAKS_CONFIG": "/nonexistent/override.toml",
            "GITLEAKS_CONFIG_TOML": "[allowlist]\nregexes = ['.*']\n",
        })
        self.assert_blocked_without_exposure(result, credential)

    def test_removed_private_file_is_still_blocked_in_history(self):
        self.stage("calendar-backup.json", '{"events": []}\n')
        self.commit_without_hooks()
        self.run_git("rm", "calendar-backup.json")
        self.commit_without_hooks()
        self.assert_blocked_without_exposure(self.guard("--history"))


if __name__ == "__main__":
    unittest.main()
