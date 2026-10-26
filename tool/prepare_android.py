#!/usr/bin/env python3
"""Generate Android scaffolding and configure release signing safely."""
from __future__ import annotations

import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ANDROID_DIR = ROOT / "android"
APP_DIR = ANDROID_DIR / "app"
PROJECT_NAME = "buy_price_assistant_gimi"
ORG = "com.abnalhag.gimi"
DISPLAY_NAME = "Buy Price Assistant HJI"


def configure_gradle_signing() -> None:
    """Configure release signing from android/key.properties when CI provides it."""
    kotlin_gradle = APP_DIR / "build.gradle.kts"
    groovy_gradle = APP_DIR / "build.gradle"
    if kotlin_gradle.is_file():
        gradle_file = kotlin_gradle
        kotlin_dsl = True
    elif groovy_gradle.is_file():
        gradle_file = groovy_gradle
        kotlin_dsl = False
    else:
        raise SystemExit("Flutter did not generate app/build.gradle.kts or app/build.gradle")

    content = gradle_file.read_text(encoding="utf-8")
    if "gimiPersistentReleaseSigning" in content:
        print(f"Release-signing support already exists in {gradle_file.name}.")
        return

    imports = "import java.io.FileInputStream\nimport java.util.Properties\n"
    content = imports + content
    plugins_match = re.search(r"(?m)^plugins\s*\{", content)
    if not plugins_match:
        raise SystemExit("Could not find the Gradle plugins block.")
    close = content.find("\n}", plugins_match.end())
    if close < 0:
        raise SystemExit("Could not locate the end of the Gradle plugins block.")
    close += 2

    properties = """
// gimiPersistentReleaseSigning: secrets are supplied by trusted CI only.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
""" if kotlin_dsl else """
// gimiPersistentReleaseSigning: secrets are supplied by trusted CI only.
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}
"""
    content = content[:close] + "\n" + properties.rstrip() + content[close:]

    android_match = re.search(r"(?m)^android\s*\{", content)
    if not android_match:
        raise SystemExit("Could not find the Gradle android block.")

    if kotlin_dsl:
        signing = """
    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }
"""
        pattern = r'(?m)^([ \t]*)signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)\s*$'
        replacement = r'\1signingConfig = if (keystorePropertiesFile.exists()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")'
    else:
        signing = """
    signingConfigs {
        release {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties.getProperty('keyAlias')
                keyPassword = keystoreProperties.getProperty('keyPassword')
                storeFile = file(keystoreProperties.getProperty('storeFile'))
                storePassword = keystoreProperties.getProperty('storePassword')
            }
        }
    }
"""
        pattern = r'(?m)^([ \t]*)signingConfig\s+signingConfigs\.debug\s*$'
        replacement = r'\1signingConfig keystorePropertiesFile.exists() ? signingConfigs.release : signingConfigs.debug'

    content = content[:android_match.end()] + signing + content[android_match.end():]
    content, count = re.subn(pattern, replacement, content, count=1)
    if count != 1:
        raise SystemExit(
            f"Could not safely replace the generated debug signing configuration in {gradle_file.name}. "
            "Build stopped to avoid an APK with uncertain signing."
        )

    gradle_file.write_text(content, encoding="utf-8")
    app_id = re.search(r'applicationId\s*(?:=\s*)?["\']([^"\']+)["\']', content)
    if app_id:
        print(f"Generated applicationId: {app_id.group(1)}")
    print(f"Configured release-signing support in {gradle_file.relative_to(ROOT)}.")


def main() -> None:
    if not ANDROID_DIR.exists():
        with tempfile.TemporaryDirectory(prefix="buy-price-android-") as temp:
            generated = Path(temp) / PROJECT_NAME
            command = [
                "flutter", "create", "--platforms=android",
                f"--project-name={PROJECT_NAME}", f"--org={ORG}",
                "--no-pub", str(generated),
            ]
            subprocess.run(command, cwd=ROOT, check=True)
            shutil.copytree(generated / "android", ANDROID_DIR)
            metadata = generated / ".metadata"
            if metadata.exists() and not (ROOT / ".metadata").exists():
                shutil.copy2(metadata, ROOT / ".metadata")
    else:
        print("Android directory already exists; preserving its platform files.")

    manifest = ANDROID_DIR / "app" / "src" / "main" / "AndroidManifest.xml"
    if not manifest.is_file():
        raise SystemExit(f"Flutter did not generate the expected manifest: {manifest}")
    content = manifest.read_text(encoding="utf-8")
    updated, count = re.subn(
        r'android:label="[^"]*"',
        f'android:label="{DISPLAY_NAME}"',
        content,
        count=1,
    )
    if count != 1:
        raise SystemExit("Could not safely set the Android application label.")
    # Use a purpose-built vector launcher icon (receipt + currency symbol).
    resources = ANDROID_DIR / "app" / "src" / "main" / "res"
    drawable_dir = resources / "drawable"
    drawable_dir.mkdir(parents=True, exist_ok=True)
    icon = drawable_dir / "hji_launcher_icon.xml"
    icon.write_text("""<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="108" android:viewportHeight="108">
    <path android:fillColor="#18365F" android:pathData="M0,0h108v108h-108z"/>
    <path android:fillColor="#FFFFFF" android:pathData="M25,20h45a5,5 0,0 1,5 5v55l-8,-5 -8,5 -8,-5 -8,5 -8,-5 -10,5z"/>
    <path android:fillColor="#18365F" android:pathData="M35,31h25v4h-25zM35,42h25v4h-25zM35,53h18v4h-18z"/>
    <path android:fillColor="#F6C453" android:pathData="M75,49a22,22 0,1 0,0.1 0z"/>
    <path android:fillColor="#18365F" android:pathData="M83,39c-2,-3 -5,-5 -9,-5 -6,0 -10,3 -10,8 0,5 4,7 10,9 4,1 5,2 5,4 0,2 -2,4 -6,4 -4,0 -7,-2 -9,-4l-3,4c2,3 5,5 9,6v5h5v-5c6,-1 9,-5 9,-10 0,-5 -4,-8 -10,-10 -4,-1 -5,-2 -5,-3 0,-2 2,-3 5,-3 3,0 5,1 7,3z"/>
</vector>
""", encoding="utf-8")
    # Android supports vector drawables directly as launcher icons.
    updated, icon_count = re.subn(
        r'android:icon="@[^"]+"',
        'android:icon="@drawable/hji_launcher_icon"',
        updated,
        count=1,
    )
    if icon_count != 1:
        raise SystemExit("Could not safely configure the launcher icon.")
    updated = re.sub(
        r'android:roundIcon="@[^"]+"',
        'android:roundIcon="@drawable/hji_launcher_icon"',
        updated,
        count=1,
    )
    manifest.write_text(updated, encoding="utf-8")
    configure_gradle_signing()
    print("Android scaffolding and signing support are ready.")


if __name__ == "__main__":
    main()
