# Stock Check (Odoo 18 + Panasonic FZ-T1)

Native Android (Flutter) app. Uses Odoo's built-in JSON-RPC API, no custom Odoo module.

## Flow
Login (pick database, Odoo login, API key) -> mandatory store (warehouse) selection -> scan -> update quantity.

## Build the APK (on a PC with Flutter + Android SDK)
    flutter pub get
    flutter test
    flutter build apk --release
APK: build/app/outputs/flutter-apk/app-release.apk

## Settings
- Server address: lib/config.dart (kOdooUrl). Adjust reasons: same file.
- Scanner: set the FZ-T1 scanner to keyboard-wedge mode with Enter suffix.

## Odoo prerequisites
- Users need an API key (My Profile > Account Security).
- Users who adjust stock need Inventory Administrator rights.
- Extra barcodes: Inventory > Settings > Product Packagings, then add packagings (qty 1 for alias barcodes).
