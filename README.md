# FieldWorker Mobile App

**FieldWorker** is the Flutter-based mobile application for field managers in the FieldScheduler system. It enables real-time GPS tracking, route management, customer visit logging, and geofencing for waste management field operations in Oyo State, Nigeria.

---

## Latest Release

| Field | Value |
|---|---|
| **Version** | 1.10.0 (build 10) |
| **Package ID** | `net.fieldscheduler.field_worker_app` |
| **Platform** | Android (arm64-v8a, armeabi-v7a, x86_64) |
| **Framework** | Flutter (Dart) |
| **Build System** | Gradle 8.3 / Kotlin 1.8.22 |
| **Min SDK** | Android 5.0+ |
| **APK** | [FieldWorker-v1.10.apk](releases/FieldWorker-v1.10.apk) |

---

## All Releases

| Version | APK | Notes |
|---|---|---|
| v1.10.0 | [FieldWorker-v1.10.apk](releases/FieldWorker-v1.10.apk) | Latest — MAF restructuring, Dalco/AFT/Yusro assignments |
| v1.9.1 | [FieldWorker-v1.9.1.apk](releases/FieldWorker-v1.9.1.apk) | Hotfix |
| v1.9.0 | [FieldWorker-v1.9.apk](releases/FieldWorker-v1.9.apk) | — |
| v1.8.0 | [FieldWorker-v1.8.apk](releases/FieldWorker-v1.8.apk) | — |
| v1.7.0 | [FieldWorker-v1.7.apk](releases/FieldWorker-v1.7.apk) | — |
| v1.6.0 | [FieldWorker-v1.6.apk](releases/FieldWorker-v1.6.apk) | — |
| v1.5.0 | [FieldWorker-v1.5.apk](releases/FieldWorker-v1.5.apk) | — |
| v1.4.0 | [FieldWorker-v1.4.apk](releases/FieldWorker-v1.4.apk) | — |
| v1.3.0 | [FieldWorker-v1.3.apk](releases/FieldWorker-v1.3.apk) | — |
| v1.2.0 | [FieldWorker-v1.2.apk](releases/FieldWorker-v1.2.apk) | — |
| v1.1.0 | [FieldWorker-v1.1.apk](releases/FieldWorker-v1.1.apk) | — |
| v1.0.0 | [FieldWorker-v1.0.apk](releases/FieldWorker-v1.0.apk) | Initial release |

---

## Features

- **Real-time GPS tracking** — field manager location broadcast to the admin dashboard every 3 seconds
- **Route management** — view assigned routes, customer list, visit status, and navigation
- **Live map view** — interactive Leaflet/OpenStreetMap map with customer pins and route overlay
- **Geofencing** — entry/exit alerts for designated service zones
- **Customer visit logging** — mark visits complete, capture notes and compliance flags
- **Offline support** — data queued locally and synced when network is restored
- **PIN-based authentication** — secure login via admin-generated PIN
- **MAF/subcontractor awareness** — displays CUSTOMERMAF assignment per customer

---

## Tech Stack

| Component | Technology |
|---|---|
| Framework | Flutter (Dart) |
| Maps | `flutter_map` + OpenStreetMap tiles |
| Location | `geolocator` + Google Play Services Location 21.2.0 |
| Icons | `cupertino_icons`, Material Icons |
| Storage | `datastore` (Android DataStore) |
| Backend API | `https://app.fieldscheduler.net` (tRPC over HTTPS) |

---

## Backend Integration

The app connects to the FieldScheduler backend at `https://app.fieldscheduler.net`. The admin dashboard source is available at:

- **Admin Dashboard**: [github.com/mottainai-devops/fieldscheduler](https://github.com/mottainai-devops/fieldscheduler)
- **APK Releases Archive**: [github.com/mottainai-devops/fieldscheduler-releases](https://github.com/mottainai-devops/fieldscheduler-releases)

---

## Installation

1. Download the latest APK from the [releases](releases/) folder
2. Enable **"Install from unknown sources"** on the Android device
3. Install the APK
4. Launch the app and enter the PIN provided by the admin dashboard

---

## Build Information (v1.10.0)

Extracted from APK metadata:

```
Package:         net.fieldscheduler.field_worker_app
Version Name:    1.10.0
Version Code:    10
Build System:    Gradle 8.3
Kotlin:          1.8.22
Flutter:         Stable channel
Play Services:   Base 18.3.0, Location 21.2.0
ABI:             arm64-v8a, armeabi-v7a, x86_64
```

---

## Organisation

**Mottainai DevOps** — [github.com/mottainai-devops](https://github.com/mottainai-devops)

> **Note:** The Flutter Dart source code is maintained locally by the development team. This repository serves as the official release and asset archive for the FieldWorker mobile application.
