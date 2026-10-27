"""Policy generation checks use a temporary app tree, without a website or personal data."""
# [01] Build a small throwaway project so these checks cannot rewrite the real app or publish a page.
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CONFIG = Path('Configuration/PrivacyPolicyContent.json')
APP_POLICY = Path('iosApp/PrivacyPolicyContent.swift')


class PrivacyPolicyGenerationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for relative in (Path('scripts/generate_privacy_policy.py'), CONFIG, APP_POLICY):
            destination = self.root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / relative, destination)
        self.script = self.root / 'scripts/generate_privacy_policy.py'
        self.policy = self.root / APP_POLICY

    # [02] Exercise the real command, including its folder choices and exit status.
    def run_generator(self, *arguments):
        return subprocess.run([sys.executable, str(self.script), *arguments],
                              cwd=self.root, capture_output=True, text=True, check=False)

    # [03] A fresh clone needs only the app configuration; generation must not create website documents by default.
    def test_default_generation_needs_no_website_and_rebuilds_the_same_app_policy(self):
        expected = self.policy.read_bytes()
        self.policy.unlink()
        result = self.run_generator()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.policy.read_bytes(), expected)
        self.assertFalse((self.root / 'docs').exists())

    # [04] App-only checks must work when public pages are deliberately absent from this checkout.
    def test_default_check_accepts_the_app_copy_without_website_files(self):
        result = self.run_generator('--check')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / 'docs').exists())

    # [05] Report a changed local policy without quietly replacing it during a read-only check.
    def test_stale_check_fails_without_rewriting_the_app_copy(self):
        drift = self.policy.read_bytes() + b'\n// Deliberate test drift\n'
        self.policy.write_bytes(drift)
        result = self.run_generator('--check')
        self.assertEqual(result.returncode, 1)
        self.assertIn(APP_POLICY.as_posix(), result.stderr)
        self.assertEqual(self.policy.read_bytes(), drift)
        self.assertFalse((self.root / 'docs').exists())

    # [06] A separate website task can still request the two matching public copies explicitly.
    def test_explicit_web_mode_checks_missing_pages_then_generates_matching_copies(self):
        missing = self.run_generator('--check', '--include-web')
        self.assertEqual(missing.returncode, 1)
        self.assertFalse((self.root / 'docs').exists())
        generated = self.run_generator('--include-web')
        self.assertEqual(generated.returncode, 0, generated.stderr)
        for name in ('privacy-policy.html', 'privacy-policy.md'):
            self.assertIn('DFE Team', (self.root / 'docs' / name).read_text())
        current = self.run_generator('--check', '--include-web')
        self.assertEqual(current.returncode, 0, current.stderr)


if __name__ == '__main__':
    unittest.main()
