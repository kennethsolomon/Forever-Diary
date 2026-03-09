# Lessons Learned

Accumulated patterns from past bugs and corrections. Read this file at the **start of any task** and apply all active lessons before proceeding. Add a new entry whenever a recurrent mistake is identified.

## Entry Format

```markdown
### [YYYY-MM-DD] [Brief title]
**Bug:** What went wrong (symptom)
**Root cause:** Why it happened
**Prevention:** What to do differently next time
```

## Active Lessons

### 2026-03-10 @Attribute(.unique) breaks CloudKit
**Bug:** SwiftData models with `@Attribute(.unique)` on `id` fields prevented CloudKit sync and caused test container creation to fail.
**Root cause:** CloudKit does not support unique constraints. The `@Attribute(.unique)` annotation was left on model `id` properties despite the plan calling for query-before-insert uniqueness.
**Prevention:** Never use `@Attribute(.unique)` in SwiftData models that sync via CloudKit. Use query-before-insert pattern instead.

### 2026-03-10 SwiftData test containers crash with container.mainContext
**Bug:** Tests that created in-memory ModelContainers and used `container.mainContext` crashed with signal trap when running in a hosted test bundle.
**Root cause:** The test host app (ForeverDiaryApp) creates its own ModelContainer. Accessing `mainContext` from a second container in the same process causes a conflict. Additionally, `@MainActor` on test classes exacerbated the issue.
**Prevention:** In SwiftData unit tests hosted by an app target: (1) Use `ModelContext(container)` instead of `container.mainContext`, (2) Do not annotate test classes with `@MainActor`, (3) Add a test-mode guard in the app's init to use in-memory local-only storage.

### 2026-03-10 CloudKit crashes test host on simulator
**Bug:** The test host app crashed during launch because CloudKit could not initialize without an iCloud account on the simulator.
**Root cause:** `ForeverDiaryApp.init()` creates a CloudKit-enabled ModelContainer first, which triggers async CloudKit mirroring that crashes when no iCloud account exists.
**Prevention:** Detect test mode with `NSClassFromString("XCTestCase") != nil` and skip CloudKit configuration entirely when running as a test host.

