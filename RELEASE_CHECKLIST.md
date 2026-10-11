# Release checklist — Buy Price Assistant GIMI

Do not call a build verified unless every applicable item is checked against actual CI output.

- [ ] Repository is the new `Buy-price-assistant-gimi` repository and contains only newly created project files.
- [ ] Commit the resolved `pubspec.lock` from the successful CI artifact to pin transitive dependency versions.
- [ ] `flutter pub get` succeeds on the selected stable Flutter toolchain.
- [ ] `dart format --output=none --set-exit-if-changed lib test` succeeds.
- [ ] `flutter analyze --fatal-infos` succeeds with no issues.
- [ ] `flutter test --reporter expanded` succeeds, including the SQLite history/search/archiving tests.
- [ ] `tool/prepare_android.py` generates Android scaffolding without overwriting existing files.
- [ ] `flutter build apk --release` succeeds.
- [ ] The expected APK exists and is non-empty.
- [ ] APK installed and opened on a real Android phone.
- [ ] Manually tested add product, partial search, Arabic digits, purchase history, sale history, app restart persistence, favorite, edit, and archive.
- [ ] Before commercial use: add and test backup/restore and verify recovery from a fresh install.

CI green alone does not replace installing and testing the APK on a device.
