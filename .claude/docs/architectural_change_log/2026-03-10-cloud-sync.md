# Architectural Change: AWS Cloud Sync

**Date:** 2026-03-10
**Type:** New Subsystem
**Branch:** feature/cloud-sync

## Summary

Replaced CloudKit auto-sync with a custom AWS-based sync architecture using DynamoDB, S3, Lambda, and Cognito. The app now uses an offline-first SwiftData model with explicit push/pull sync to AWS.

## What Changed

- **Authentication**: Anonymous Cognito Identity Pool provides temporary IAM credentials
- **Data sync**: SwiftData entries/templates/check-ins pushed to DynamoDB via Lambda API
- **Photo sync**: Photos uploaded to S3 via presigned URLs; metadata stored in DynamoDB
- **API signing**: Custom SigV4 implementation using CryptoKit HMAC-SHA256

## Before & After

| Aspect | Before | After |
|--------|--------|-------|
| Sync backend | CloudKit (automatic) | DynamoDB + S3 (explicit push/pull) |
| Auth | iCloud account required | Anonymous Cognito (no account needed) |
| Photo storage | CloudKit assets | S3 with presigned URLs |
| Conflict resolution | CloudKit merge | Last-write-wins by updatedAt |
| API layer | None (CloudKit framework) | API Gateway + Lambda + SigV4 |
| Developer account | Paid Apple Developer required | Free Apple Developer + AWS |

## New Files

| File | Purpose |
|------|---------|
| `ForeverDiary/Services/AWSConfig.swift` | Region, pool ID, API URL constants |
| `ForeverDiary/Services/CognitoAuthService.swift` | Anonymous auth + credential refresh |
| `ForeverDiary/Services/APIClient.swift` | SigV4-signed HTTP client |
| `ForeverDiary/Services/SyncService.swift` | Push/pull sync orchestration |
| `ForeverDiary/Services/KeychainHelper.swift` | Keychain CRUD for identity persistence |
| `aws/lambda/index.mjs` | Lambda handler: /sync (push/pull) + /presign |

## Affected Components

- **ForeverDiaryApp.swift** — Creates auth + sync services, starts sync on launch
- **HomeView.swift** — Triggers debounced sync on diary text save
- **EntryDetailView.swift** — Triggers debounced sync on text/location/check-in changes
- **SettingsView.swift** — Displays sync status, last sync date, manual sync button
- **All models** — Added `syncStatus`, `lastSyncedAt` fields; PhotoAsset added `s3Key`, `s3ThumbKey`

## DynamoDB Schema

- **Table**: `forever-diary`
- **PK**: `userId` (Cognito identity ID)
- **SK prefixes**: `entry#MM-DD#YYYY`, `template#UUID`, `checkin#MM-DD#YYYY#UUID`, `photo#UUID`

## Migration / Compatibility

- No data migration needed — new fields have defaults
- CloudKit entitlements remain in project.yml but `cloudKitDatabase: .none` is used
- Existing local SwiftData entries get `syncStatus: "pending"` and sync on first launch
