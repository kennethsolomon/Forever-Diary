# TODO — Cloud Sync (AWS)

## Goal
Add AWS cloud sync (DynamoDB + S3 + Cognito) so diary data persists across app reinstalls. SwiftData remains local source of truth; SyncService pushes/pulls in background.

## Lessons Applied
- No `@Attribute(.unique)` on any model fields
- Tests use `ModelContext(container)`, not `container.mainContext`
- Test host guard (`NSClassFromString("XCTestCase")`) skips network services

---

## Phase 1: AWS Infrastructure Setup

- [ ] 1.1 Create `aws/` directory with infrastructure setup script (Cognito Identity Pool, DynamoDB table, S3 bucket, IAM roles, API Gateway, Lambda)
- [ ] 1.2 Create DynamoDB single table `forever-diary` — PK: `userId` (String), SK: `entityType#key` (String) — on-demand billing
- [ ] 1.3 Create S3 bucket `forever-diary-photos-{suffix}` with private ACL, lifecycle rule for cost optimization
- [ ] 1.4 Create Cognito Identity Pool with unauthenticated access — returns stable `identityId`
- [ ] 1.5 Create IAM role for unauthenticated Cognito users: DynamoDB access scoped to own `userId` partition, S3 access scoped to own `userId/` prefix
- [ ] 1.6 Write Lambda function `forever-diary-api` (Node.js): handles `/sync` (batch put/query DynamoDB) and `/presign` (generate S3 presigned URLs)
- [ ] 1.7 Create API Gateway REST API with IAM auth, route to Lambda, deploy `prod` stage
- [ ] 1.8 Verify: `aws dynamodb scan`, curl presigned URL upload

**Verify:** Test item in DynamoDB, test file in S3 bucket.

## Phase 2: iOS — Auth & Config

- [ ] 2.1 Create `ForeverDiary/Services/AWSConfig.swift` — region, API Gateway URL, Cognito Identity Pool ID, S3 bucket name (non-secret constants)
- [ ] 2.2 Create `ForeverDiary/Services/CognitoAuthService.swift` — anonymous auth via Cognito REST API (`GetId` + `GetCredentialsForIdentity`), cache credentials in memory, store `identityId` in Keychain
- [ ] 2.3 Create `ForeverDiary/Services/KeychainHelper.swift` — minimal Keychain wrapper for storing/retrieving `identityId` string
- [ ] 2.4 Verify: app launches, prints Cognito `identityId`, persists in Keychain

**Verify:** Build succeeds, `identityId` logged on launch.

## Phase 3: iOS — Sync Engine

- [ ] 3.1 Add `syncStatus` (String, default "pending") and `lastSyncedAt` (Date?) properties to DiaryEntry, CheckInTemplate, CheckInValue, PhotoAsset
- [ ] 3.2 Add `s3Key` (String?) and `s3ThumbKey` (String?) to PhotoAsset model
- [ ] 3.3 Create `ForeverDiary/Services/APIClient.swift` — handles signed requests to API Gateway using Cognito credentials (SigV4 or IAM token in header)
- [ ] 3.4 Create `ForeverDiary/Services/SyncService.swift` (`@Observable`) — `syncAll()`, `pushPending()`, `pullRemote()`, `uploadPhotos()`, `downloadPhotos()`
- [ ] 3.5 Implement `pushPending()`: query SwiftData for `syncStatus == "pending"`, serialize to JSON, POST to `/sync`, mark "synced" on success
- [ ] 3.6 Implement `pullRemote()`: GET `/sync?since={lastSyncTimestamp}`, upsert into SwiftData (last-write-wins on `updatedAt`)
- [ ] 3.7 Implement `uploadPhotos()`: for pending PhotoAssets, POST `/presign` for upload URL, PUT imageData + thumbnailData to S3, save s3Key
- [ ] 3.8 Implement `downloadPhotos()`: for PhotoAssets with s3Key but empty local data, GET `/presign` for download URL, fetch and store locally
- [ ] 3.9 Verify: create entry → push to DynamoDB → verify in AWS console

**Verify:** Entry visible in DynamoDB after app save.

## Phase 4: iOS — App Integration

- [ ] 4.1 Initialize CognitoAuthService and SyncService in `ForeverDiaryApp.swift` (skip in test mode)
- [ ] 4.2 Trigger `syncAll()` on app launch (2s delay, non-blocking)
- [ ] 4.3 Trigger `pushPending()` after saves in HomeView, EntryDetailView, SettingsView (debounced 5s)
- [ ] 4.4 Add "Sync Now" button + last sync time display in SettingsView
- [ ] 4.5 Add sync status indicator in HomeView header (cloud icon: synced/syncing/offline)
- [ ] 4.6 Handle network errors: items stay "pending", retry on next sync cycle
- [ ] 4.7 Verify: full round-trip — create entry → sync → delete app → reinstall → data restored

**Verify:** Reinstall app on device, all entries + photos restore.

## Phase 5: Edge Cases & Hardening

- [ ] 5.1 First-launch detection: if SwiftData empty but Keychain has identityId → trigger full pull
- [ ] 5.2 Cognito credential refresh: tokens expire after 1 hour, refresh before API calls
- [ ] 5.3 Large photo download: download thumbnails first, full images on-demand when user opens entry
- [ ] 5.4 Sync guard: skip all sync in test mode (`NSClassFromString("XCTestCase")`)
- [ ] 5.5 Handle deleted entries: add `isDeleted` soft-delete flag, sync deletions to cloud
- [ ] 5.6 Verify: airplane mode → create entries → go online → entries sync; reinstall → restore works

**Verify:** Build succeeds, 31 existing tests pass, offline→online sync works, reinstall restores all data.

---

## Verification Commands
```bash
# Build
xcodebuild -scheme ForeverDiary -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Tests
xcodebuild -scheme ForeverDiary -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# AWS verification
aws dynamodb scan --table-name forever-diary --region us-east-1
aws s3 ls s3://forever-diary-photos-{suffix}/
```

## Acceptance Criteria
1. App works 100% offline — no regression from v1
2. New/edited entries sync to DynamoDB within 10 seconds when online
3. Photos upload to S3 and restore after reinstall
4. Cognito identity persists in Keychain across reinstalls
5. No AWS secrets in app source code
6. All 31 existing tests still pass
7. Settings shows last sync time and manual sync button
8. Home screen shows sync status indicator

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| AWS SDK too heavy | Use URLSession + REST APIs, no aws-sdk-swift dependency |
| Cognito identity lost on reinstall | Store identityId in Keychain (survives uninstall) |
| Photo upload fails mid-way | Track each photo independently; retry pending on next sync |
| DynamoDB throttling | On-demand billing handles bursts; diary volume is tiny |
| Sync conflicts | Last-write-wins on `updatedAt` — sufficient for single-user |
| API Gateway auth complexity | Use IAM auth with Cognito temporary credentials — well-documented pattern |
