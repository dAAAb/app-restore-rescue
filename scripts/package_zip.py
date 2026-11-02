#!/usr/bin/env python3
"""Create a ZIP from an explicit app-bundle/document allowlist.

ZIP entries have normalized timestamps and modes, and no extended attributes,
resource forks, machine ownership, build caches, logs, or Git metadata.
"""

from pathlib import Path
import sys
import zipfile

STANDALONE = {"README.md", "README.ja.md", "README.ko.md", "README.zh-TW.md", "LICENSE", "PRIVACY.md", "BUILD-INFO.txt"}
BUNDLE = {
    "AppRestoreRescue.app/Contents/Info.plist",
    "AppRestoreRescue.app/Contents/PkgInfo",
    "AppRestoreRescue.app/Contents/Resources/AppIcon.icns",
    "AppRestoreRescue.app/Contents/MacOS/AppRestoreRescue",
    "AppRestoreRescue.app/Contents/_CodeSignature/CodeResources",
}


def package(stage: Path, output: Path) -> None:
    files: list[tuple[str, Path]] = []
    for path in sorted(stage.rglob("*")):
        if path.is_symlink():
            raise ValueError("Release staging contains a symlink")
        if not path.is_file():
            continue
        name = path.relative_to(stage).as_posix()
        if name not in STANDALONE | BUNDLE:
            raise ValueError(f"Unexpected release file: {name}")
        files.append((name, path))
    present = {name for name, _ in files}
    if present != STANDALONE | BUNDLE:
        raise ValueError("Required release files are missing")
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, path in files:
            info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            info.create_system = 3
            executable = name.endswith("/MacOS/AppRestoreRescue")
            info.external_attr = (0o100755 if executable else 0o100644) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, path.read_bytes())


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: package_zip.py STAGING_DIRECTORY OUTPUT_ZIP")
    package(Path(sys.argv[1]), Path(sys.argv[2]))
