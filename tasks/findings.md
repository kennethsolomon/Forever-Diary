# Forever Diary — Cloud Sync Feature Findings

## Problem Statement
App data is lost on reinstall. User reinstalls weekly on personal device with a free Apple Developer account (no CloudKit). Need cloud persistence for diary entries and photos.

## Key Decisions

### Backend: All-AWS
- **DynamoDB** for structured data (entries, check-ins, templates)
- **S3** for photo storage (JPEG blobs)
- **Cognito** for anonymous device-based auth (no login screen)
- **API Gateway + Lambda** for presigned S3 URLs and sync API
- Rationale: single ecosystem, user has existing AWS account, 25GB DynamoDB free forever, ~$0.50/month after year 1

### Architecture: Offline-first with background sync
```
SwiftUI Views
    ↓ @Query
SwiftData (local, offline-first, source of truth for UI)
    ↓ SyncService (background)
Cognito (identity) → API Gateway → Lambda → DynamoDB + S3
```

### Sync Strategy
- SwiftData remains the local source of truth — all reads come from SwiftData
- SyncService runs in background: pushes local changes to AWS, pulls remote changes on app launch / reinstall
- Conflict resolution: last-write-wins based on `updatedAt` timestamp
- Photos: upload to S3 via presigned URL, store S3 key in DynamoDB and SwiftData
- On reinstall: Cognito restores identity → pull DynamoDB entries → lazy-download photos from S3

### Data Flow
- **Write path:** User edits → SwiftData save → mark dirty → SyncService uploads to DynamoDB/S3
- **Read path (normal):** SwiftData @Query (no network)
- **Read path (restore):** Cognito auth → DynamoDB scan → insert into SwiftData → S3 photo download (lazy)

### DynamoDB Schema
- **Table: diary-entries** — PK: `userId`, SK: `{monthDayKey}#{year}` — stores text, location, weekday, timestamps
- **Table: check-in-values** — PK: `userId`, SK: `{entryKey}#{templateId}` — stores bool/text/number values
- **Table: check-in-templates** — PK: `userId`, SK: `{templateId}` — stores label, type, isActive, sortOrder
- **Table: photo-assets** — PK: `userId`, SK: `{entryKey}#{photoId}` — stores S3 key, createdAt

### S3 Structure
- Bucket: `forever-diary-photos`
- Key pattern: `{userId}/{monthDayKey}-{year}/{photoId}.jpg`
- Thumbnails: `{userId}/{monthDayKey}-{year}/{photoId}_thumb.jpg`

### Auth
- Cognito Identity Pool with unauthenticated access (anonymous)
- Device gets a stable `identityId` — used as `userId` partition key
- Future: add Apple Sign-In as an authenticated provider for cross-device sync

### SwiftData Changes
- Add `syncStatus` field to models: `.synced`, `.pending`, `.conflict`
- Add `lastSyncedAt` timestamp
- SyncService queries for `.pending` items and uploads them

### Lambda Functions
- `generatePresignedUrl` — returns S3 upload/download URL for photos
- `syncEntries` — batch upsert/fetch entries from DynamoDB
- Optional: could use API Gateway direct DynamoDB integration to skip Lambda for simple CRUD

### Security Constraints
- No AWS credentials in the app — all access via Cognito temporary credentials
- S3 bucket policy: users can only read/write their own `{userId}/` prefix
- DynamoDB: partition key = `userId`, enforced by IAM policy on Cognito role
- Presigned URLs expire after 15 minutes

## Chosen Approach & Rationale
All-AWS with offline-first SwiftData. Single ecosystem, generous free tier (25GB DynamoDB forever, ~$0.50/month for S3 after year 1). SwiftData stays as local cache — no UI changes needed. SyncService is a new background layer that pushes/pulls data.

## Open Questions
- None — direction is locked in.

## Out of Scope
- Real-time collaborative sync (single user app)
- Cross-device conflict resolution UI (last-write-wins is sufficient)
- Photo editing/cropping in cloud
