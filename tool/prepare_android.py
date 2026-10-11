#!/usr/bin/env python3
# Generate Android platform scaffolding using the runner's installed Flutter SDK.
# The app source is retained as-is; existing Android files are never overwritten.
from __future__ import annotations

import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ANDROID_DIR = ROOT / "android"
PROJECT_NAME = "buy_price_assistant_gimi"
ORG = "com.abnalhag.gimi"
DISPLAY_NAME = "Buy Price Assistant GIMI"


def main() -> None:
    if ANDROID_DIR.exists():
        print("An android/ directory already exists; preserving it so Flutter's build can validate it.")
        return

    with tempfile.TemporaryDirectory(prefix="buy-price-android-") as temp:
        generated = Path(temp) / PROJECT_NAME
        command = [
            "flutter",
            "create",
            "--platforms=android",
            f"--project-name={PROJECT_NAME}",
            f"--org={ORG}",
            "--no-pub",
            str(generated),
        ]
        subprocess.run(command, cwd=ROOT, check=True)

        shutil.copytree(generated / "android", ANDROID_DIR)
        metadata = generated / ".metadata"
        if metadata.exists() and not (ROOT / ".metadata").exists():
            shutil.copy2(metadata, ROOT / ".metadata")

    manifest = ANDROID_DIR / "app" / "src" / "main" / "AndroidManifest.xml"
    if not manifest.is_file():
        raise SystemExit(f"Flutter did not generate the expected manifest: {manifest}")

    content = manifest.read_text(encoding="utf-8")
    import re

    updated, count = re.subn(r'android:label="[^"]*"', f'android:label="{DISPLAY_NAME}"', content, count=1)
    if count != 1:
        raise SystemExit("Could not safely set the Android application label in AndroidManifest.xml")
    manifest.write_text(updated, encoding="utf-8")
    print("Android scaffolding generated successfully; application label set.")


if __name__ == "__main__":
    main()
