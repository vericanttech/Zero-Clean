# Zero-Clean

**Structured product photo collection for training-ready datasets — zero cleaning required afterward.**

Zero-Clean helps you collect and label photos of specific products in real stores (by store, product, and situation) so that when you’re done, the dataset is ready for training.

- **Dashboard** — Progress per store and product (single / shelf / checkout).
- **Capture** — Take photos with store, variant, and context attached.
- **Review** — Draw bounding boxes, assign labels, verify annotations.
- **Setup** — Manage stores and product variants (categories, brands, packaging).

See [PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md) for a full description of the app and workflow.

---

## Prerequisites

- [Flutter](https://flutter.dev) (SDK >=3.0.0)
- Firebase project (Auth, Firestore, Storage)

### Firebase config (do not commit)

**Do not commit real API keys or config files.** Add them locally after cloning:

- **Android:** Download `google-services.json` from [Firebase Console](https://console.firebase.google.com) → Project → Project settings → Your apps → Android app, and place it in `android/app/google-services.json`. Use `android/app/google-services.json.example` as a structure reference.
- **iOS:** Download `GoogleService-Info.plist` and place it in `ios/Runner/GoogleService-Info.plist`.

---

## Getting started

```bash
git clone https://github.com/vericanttech/Zero-Clean.git
cd Zero-Clean
git checkout ios-bundle   # or your branch
flutter pub get
flutter run
```

- **Android:** Connect a device or use an emulator; `flutter run` will build and install.
- **iOS:** Build on macOS: `flutter build ios` (or open `ios/Runner.xcworkspace` in Xcode and run from there). Requires Apple Developer setup and `GoogleService-Info.plist` in `ios/Runner/`.

---

## Tech stack

- Flutter (Dart)
- Firebase (Auth, Firestore, Storage)
- SQLite (local cache), sync with Firestore when online
- Camera & file system for capture and sidecar JSON annotations

---

## License

Proprietary — Vericant Tech.
