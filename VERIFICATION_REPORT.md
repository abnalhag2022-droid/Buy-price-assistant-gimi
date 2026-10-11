# Verification report — Buy Price Assistant GIMI

## Completed in the authoring environment

- Created a new source tree from newly authored application files; no pre-existing project source was imported.
- Parsed `pubspec.yaml`, `analysis_options.yaml`, and `.github/workflows/android-ci.yml` as YAML.
- Extracted and executed the SQLite table/index DDL from `lib/data/app_database.dart` against Python's SQLite engine.
- Exercised representative insert/query behavior for multiple purchase entries, latest purchase selection, latest sale selection, entry counts, and archiving while retaining history.
- Added Dart unit tests for Arabic normalization, localized-number parsing, money formatting, SQL LIKE escaping, and database history/search/archiving/validation behavior.
- Added a pinned Flutter stable toolchain in GitHub Actions, test dependencies, Android platform generation from that same Flutter SDK, a release-mode APK build, and artifact upload steps.

## Not yet verified by execution

The current authoring container has Java and Python but does not have Flutter, Dart, Gradle, or Android SDK installed, and it cannot download the Flutter SDK from the container shell. Therefore `dart format`, `flutter analyze`, `flutter test`, and `flutter build apk --release` have **not** been executed here. Their actual result must be read from the first GitHub Actions run. No statement in this report should be interpreted as claiming that the APK has already built successfully.

## Required gate before installation or daily business use

1. Create the new GitHub repository and push the source.
2. Require the full `Android CI` workflow to pass, including tests and APK existence check. Fix any observed CI failures before proceeding.
3. Install the generated APK on an Android device and manually test adding/editing a product, Arabic partial search, purchase and sale entries, history ordering, persistence after force-close/reopen, favorites, and archiving.
4. Before relying on the database for important business records, add and test in-app backup/export and restore. The initial release does not yet implement that feature.
