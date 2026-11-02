"""Packaging/privacy regression tests; no Apple tools or devices are used."""

from pathlib import Path
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import package_zip
import privacy_audit


class PackagingTests(unittest.TestCase):
    def make_stage(self, directory: Path) -> Path:
        stage = directory / "stage"
        for name in package_zip.STANDALONE | package_zip.BUNDLE:
            path = stage / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"synthetic fixture")
        return stage

    def test_archive_contains_only_allowlisted_files_and_normalized_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            stage = self.make_stage(root)
            first = root / "first.zip"
            second = root / "second.zip"
            package_zip.package(stage, first)
            package_zip.package(stage, second)
            self.assertEqual(first.read_bytes(), second.read_bytes())
            with zipfile.ZipFile(first) as archive:
                self.assertEqual(set(archive.namelist()), package_zip.STANDALONE | package_zip.BUNDLE)
                for entry in archive.infolist():
                    self.assertEqual(entry.date_time, (2026, 1, 1, 0, 0, 0))
                    self.assertEqual(entry.extra, b"")
                    self.assertEqual(entry.comment, b"")
                    mode = (entry.external_attr >> 16) & 0o777
                    expected = 0o755 if entry.filename.endswith("/MacOS/AppRestoreRescue") else 0o644
                    self.assertEqual(mode, expected)

    def test_archive_rejects_extra_private_file(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            stage = self.make_stage(root)
            (stage / ".env").write_text("private fixture")
            with self.assertRaises(ValueError):
                package_zip.package(stage, root / "out.zip")

    def test_archive_rejects_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            stage = self.make_stage(root)
            (stage / "unexpected").symlink_to(root)
            with self.assertRaises(ValueError):
                package_zip.package(stage, root / "out.zip")

    def test_archive_rejects_missing_signature_file(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            stage = self.make_stage(root)
            (stage / "AppRestoreRescue.app/Contents/_CodeSignature/CodeResources").unlink()
            with self.assertRaises(ValueError):
                package_zip.package(stage, root / "out.zip")


class PrivacyAuditTests(unittest.TestCase):
    def test_rejects_diagnostic_archives_and_secret_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "docs").mkdir()
            (root / "docs" / "capture.logarchive").mkdir()
            (root / "docs" / ".env").write_text("fixture")
            self.assertEqual(len(privacy_audit.inspect(root)), 2)

    def test_does_not_echo_credentials_or_identifiers(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            identifier = "1234" + "5678-" + "0123456789" + "abcdef"
            secret = "ghp_" + "A" * 36
            (root / "README.md").write_text(identifier + "\n" + secret)
            findings = privacy_audit.inspect(root)
            self.assertEqual(len(findings), 2)
            self.assertNotIn(identifier, "\n".join(findings))
            self.assertNotIn(secret, "\n".join(findings))

    def test_allows_obviously_synthetic_test_identifiers(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "README.md").write_text("00000000-0000000000000000")
            self.assertEqual(privacy_audit.inspect(root), [])


if __name__ == "__main__":
    unittest.main()
