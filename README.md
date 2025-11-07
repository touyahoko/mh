OssanSnipeTool - Flutter prototype
=================================

Contents:
- lib/main.dart  (main app)
- pubspec.yaml

What I built for you:
- Flutter app that reproduces LCG RNG, loads seed lists and a merged charm JSON,
  and searches for target RNG values or matches to the charm table's 判定値 columns.
- Includes a high-precision timer UI for snipe timing.

How to build APK locally:
1. Install Flutter SDK: https://flutter.dev/docs/get-started/install
2. In this project folder run:
   flutter pub get
   flutter build apk --release
3. The release APK will be at: build/app/outputs/flutter-apk/app-release.apk
   For debugging use: flutter run (device connected) or build apk --debug

GitHub Actions (CI) example:
- There's a .github/workflows/flutter.yml file included that builds an APK on push.

Notes:
- You must supply the merged charm JSON (mh4g_charm_tables.json) and push it to device or include in assets.
- If you want me to produce a signed release APK, you'll need to provide a keystore and the signing config.