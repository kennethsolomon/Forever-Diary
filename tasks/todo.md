# UI Polish + Sign in with Apple

## Goal
Four improvements: remove the view/write mode toggle, build a paginated photo gallery viewer, redesign calendar day cells as stacked photo cards, and add Sign in with Apple authentication with per-account data isolation.

## Lessons Applied
- No `@Attribute(.unique)` on any SwiftData model fields
- Tests use `ModelContext(container)`, not `container.mainContext`
- Test host guard skips CloudKit AND auth services (extend guard to AppleAuthService/CognitoAuthService init)
- Test host guard: `NSClassFromString("XCTestCase") != nil`

---

## Phase 1: Remove View/Write Mode Toggle (Feature A)

- [x] 1.1 Remove from `HomeView.swift`: `@State private var isViewMode`, toolbar `Button` (eye/pencil icon), `MarkdownTextView` branch in `textEditor`, and the `isViewMode`/`isTextEditorFocused` coupling in the toolbar action
- [x] 1.2 Remove from `EntryDetailView.swift`: `@State private var isViewMode`, `@FocusState private var isDiaryFocused`, toolbar `Button`, `MarkdownTextView` branch in `diarySection`, and the focus-toggle side effects
- [x] 1.3 Delete `ForeverDiary/Views/Components/MarkdownTextView.swift`
- [x] 1.4 Delete `ForeverDiaryTests/MarkdownTests.swift`
- [x] 1.5 Build succeeds — `xcodebuild build`

---

## Phase 2: Calendar Day Cards + Stacked Display (Feature C)

- [x] 2.1 In `CalendarBrowserView.swift` — update `DayCell` aspect ratio from `aspectRatio(1)` to `aspectRatio(3/4, contentMode: .fit)` (portrait card)
- [x] 2.2 Replace all `Circle()` and `clipShape(Circle())` in `DayCell` with `RoundedRectangle(cornerRadius: 8)` and `clipShape(RoundedRectangle(cornerRadius: 8))`
- [x] 2.3 **No-photo single entry:** Card bg = `surfaceCard` at 0.5 opacity, day number centered, `textSecondary`; today variant: full `surfaceCard` bg with 1.5px teal border + teal bold day number
- [x] 2.4 **Single photo:** Photo fills card via `.scaledToFill()` + `.clipShape(RoundedRectangle)`, day number bottom-left in white `.caption` bold with drop shadow
- [x] 2.5 **Stacked deck (2+ entries OR 3+ photos):** `ZStack(alignment: .top)` with:
  - Card 3 (bottom): `RoundedRectangle.fill(surfaceCard).opacity(0.5)`, `rotationEffect(.degrees(2.5))`, `offset(y: 8)`
  - Card 2 (middle): `RoundedRectangle.fill(surfaceCard).opacity(0.75)`, `rotationEffect(.degrees(-1.5))`, `offset(y: 4)`
  - Card 1 (top): 0° rotation, 0 offset, photo or surfaceCard fill, day number bottom-left
  - Entire `ZStack` wrapped in `.padding(.bottom, 10)` to reserve space for peek
- [x] 2.6 Count badge: 16×16 teal circle, white `.system(size: 9, weight: .bold)`, pinned `.topTrailing` at `offset(x: 3, y: -3)` — shown when `(totalEntries > 1 || totalPhotoCount > 3)` — displays `totalEntries` count
- [x] 2.7 Update `LazyVGrid` grid spacing from `spacing: 4` to `spacing: 3`
- [x] 2.8 Build succeeds — `xcodebuild build`

---

## Phase 3: Photo Gallery Viewer (Feature B)

- [x] 3.1 Create `ForeverDiary/Views/Components/PhotoGalleryView.swift`:
  - State: `@State private var currentIndex: Int`, `@State private var dragOffset: CGSize`, `@State private var dragOpacity: Double = 1.0`, `@State private var scale: CGFloat = 1.0`
  - Input: `photos: [PhotoAsset]`, `startIndex: Int`
  - `@Environment(\.dismiss) private var dismiss`
- [x] 3.2 Full-screen ZStack on black bg (`.ignoresSafeArea()`):
  - `TabView(selection: $currentIndex) { ForEach(photos) { ... } }.tabViewStyle(.page(indexDisplayMode: .never))`
  - Each page: `Image(uiImage: ...).resizable().scaledToFit()` — NO `.ignoresSafeArea()` on image — centered in screen
- [x] 3.3 Overlay controls (not inside TabView):
  - Top-left: X close button — `"xmark"` in a 36×36 `Color.white.opacity(0.15)` circle, padding 16 from safe area — `Button { dismiss() }`
  - Top-right: counter `"\(currentIndex + 1) / \(photos.count)"` — `.caption`, white, padding 16
  - Bottom: pagination dots — `ForEach(photos.indices)` → circle 6px, teal if current, `white.opacity(0.3)` otherwise
- [x] 3.4 Swipe-down-to-dismiss: `DragGesture` on outer ZStack → `dragOffset = value.translation` when height > 0; `dragOpacity = max(0, 1 - (dragOffset.height / 250))`; on ended: if height > 80 → dismiss, else spring-reset offset + opacity
- [x] 3.5 Pinch-to-zoom per photo: `MagnificationGesture` → `scale = value.clamped(1.0, 4.0)`; double-tap → `withAnimation { scale = 1.0 }`. Apply `scaleEffect(scale)` to the image
- [x] 3.6 Update `EntryDetailView.swift`:
  - Replace `@State private var fullScreenPhoto: PhotoAsset?` with `@State private var galleryStartIndex: Int?`
  - Replace `.fullScreenCover(item: $fullScreenPhoto)` with `.fullScreenCover(isPresented: Binding(get: { galleryStartIndex != nil }, set: { if !$0 { galleryStartIndex = nil } })) { PhotoGalleryView(photos: sortedPhotos, startIndex: galleryStartIndex ?? 0) }`
  - On thumbnail tap: `galleryStartIndex = index` (use `enumerated()` to get index)
  - Extract `sortedPhotos` as a computed property: `entry?.safePhotoAssets.sorted(by: { $0.createdAt < $1.createdAt }) ?? []`
  - Delete `PhotoFullScreenView` struct at bottom of file
- [x] 3.7 Update `TimelineView.swift` — `YearSummaryCard`:
  - Add `@State private var galleryStartIndex: Int?` to `YearSummaryCard`
  - Increase thumbnail size from 40×40 to 64×64 (both width and height)
  - Wrap each thumbnail `Image` in a `Button` that sets `galleryStartIndex = index`
  - Add `.fullScreenCover(isPresented:) { PhotoGalleryView(photos: sortedPhotos, startIndex: ...) }` to `YearSummaryCard`
- [x] 3.8 Build succeeds — `xcodebuild build`

---

## Phase 4: Sign in with Apple + Account System (Feature D)

- [x] 4.1 Add Sign in with Apple entitlement to `ForeverDiary/ForeverDiary.entitlements`:
  ```xml
  <key>com.apple.developer.applesignin</key>
  <array><string>Default</string></array>
  ```
- [x] 4.2 Create `ForeverDiary/Services/AppleAuthService.swift`:
  - `import AuthenticationServices`
  - `@Observable final class AppleAuthService: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding`
  - `func signIn() async throws -> (identityToken: String, fullName: String?, email: String?)` — uses `ASAuthorizationAppleIDProvider`, wraps delegate callbacks in `CheckedContinuation`
  - `presentationAnchor` returns the key window
- [x] 4.3 Update `ForeverDiary/Services/CognitoAuthService.swift`:
  - Add `private(set) var isAuthenticatedWithApple = false` state
  - Add `func authenticateWithApple(identityToken: String, displayName: String?) async throws -> String` method:
    - Builds `Logins: ["appleid.apple.com": identityToken]`
    - Calls `getOrCreateIdentity(logins:)` — updated to accept optional logins dict
    - Calls `getCredentials(identityId:logins:)` — passes logins for authenticated flow
    - Stores identityId in Keychain, sets `isAuthenticated = true`, `isAuthenticatedWithApple = true`
    - Saves `displayName` to Keychain under key `"appleDisplayName"`
  - Update existing `authenticate()` to call the new `getOrCreateIdentity(logins: nil)` path (anonymous, unchanged)
  - Add `func signOut()` — clears Keychain (identityId, appleDisplayName), resets state flags
  - Add `var displayName: String?` computed property — reads from Keychain
- [x] 4.4 Create `ForeverDiary/Views/Auth/SignInView.swift`:
  - Full-screen dark bg (`#222831`)
  - Decorative dot-oval motif: 12 faint teal circles (`opacity(0.10)`) arranged in a ring using polar coordinates (Canvas or explicit positions)
  - App name: `Text("Forever Diary").font(.system(.largeTitle, design: .serif, weight: .light))`
  - Tagline: `Text("Every day, a story.\nEvery year, a life.")` — `.subheadline`, `.rounded`, `textSecondary`, centered, multiline
  - `SignInWithAppleButton(.continue, onRequest:, onCompletion:)` — `.frame(height: 50).padding(.horizontal, 40)` — `.signInWithAppleButtonStyle(.white)` (dark bg)
  - On completion: call `appleAuthService.handleCompletion(result:)` → `cognitoAuthService.authenticateWithApple(...)` → if success, `isAuthenticated = true`
  - Privacy caption below: `"Your diary stays private. Synced securely to your iCloud account."` — `.caption`, `textSecondary`
  - Staggered appear animation: dots `.opacity` 0→1 in 0.4s, title slides up + fades 0.5s (delay 0.2s), button fades 0.4s (delay 0.5s)
  - Error handling: `@State private var errorMessage: String?` — show as `.alert` on sign-in failure
- [x] 4.5 Update `ForeverDiary/App/ForeverDiaryApp.swift`:
  - Add `@State private var cognitoAuth = CognitoAuthService()` and `@State private var appleAuth = AppleAuthService()`
  - Auth gate in `WindowGroup`: `if cognitoAuth.isAuthenticatedWithApple { ContentView()... } else { SignInView()... }`
  - Extend test-host guard to skip auth initialization: both services initialized only when `!isTestHost`
  - Pass `cognitoAuth` and `appleAuth` as `.environment()` objects to both `SignInView` and `ContentView`
- [x] 4.6 Update `ForeverDiary/Views/Settings/SettingsView.swift`:
  - **Remove** `EditButton()` from `.toolbar`
  - **Add Account section** (first section, above Appearance):
    ```
    Section("Account") {
        HStack {
            Image(systemName: "apple.logo").foregroundStyle(Color("textPrimary"))
            VStack(alignment: .leading) {
                Text(cognitoAuth.displayName ?? "Apple Account").font(.body.rounded)
                Text("Signed in with Apple").font(.caption).foregroundStyle(Color("textSecondary"))
            }
        }
        Button("Sign Out", role: .destructive) { showSignOutAlert = true }
    }
    ```
  - Sign Out alert: "Sign out? You'll need to sign in again to access your diary." → calls `cognitoAuth.signOut()`
  - **Move Edit into Habit Templates header**: change `Section { ... } header: { Text("Habit Templates") }` to custom header `HStack { Text("Habit Templates"); Spacer(); Button { editMode toggle } label: { Image(systemName: isEditing ? "checkmark.circle.fill" : "pencil.circle").foregroundStyle(Color("accentBright")) } }`
  - Manage `@State private var editMode: EditMode = .inactive`, apply `.environment(\.editMode, $editMode)` on the `List`
  - `.contentTransition(.symbolEffect(.replace))` on the pencil/checkmark icon swap
- [x] 4.7 `xcodegen generate` — pick up new `Auth/SignInView.swift` and `Services/AppleAuthService.swift`
- [x] 4.8 Build succeeds — `xcodebuild build`

---

## Phase 5: Final Verification

- [x] 5.1 Full test run — `xcodebuild test` — all tests pass (baseline: 76 after MarkdownTests removal)
- [x] 5.2 Manual smoke check list:
  - HomeView: no eye icon in toolbar, text editor works normally
  - EntryDetailView: no eye icon, tap photos opens gallery, swipe between photos, pinch to zoom, swipe down to dismiss
  - YearSummaryCard: 64×64 thumbnails, tap opens gallery
  - Calendar: portrait cards, today has teal border, multi-photo days show stacked deck, count badge visible
  - App launch (fresh install): shows SignInView
  - Settings: Account section at top, pencil.circle in Habit Templates header, EditButton gone from toolbar

---

## Verification Commands

```bash
# Regenerate Xcode project (after Phase 4 adds new files)
xcodegen generate

# Build
xcodebuild -scheme ForeverDiary -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
# Expected: BUILD SUCCEEDED

# Tests
xcodebuild test -scheme ForeverDiary -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -10
# Expected: 76+ tests pass (89 baseline minus 13 MarkdownTests)
```

---

## Acceptance Criteria

1. No eye/view-mode icon appears anywhere in the app
2. `MarkdownTextView.swift` and `MarkdownTests.swift` are deleted
3. Tapping any photo in `EntryDetailView` opens full-screen gallery at the correct index
4. Gallery allows swiping between all entry photos, shows `N / Total` counter
5. Pinch-to-zoom and swipe-down-to-dismiss work on the gallery
6. `YearSummaryCard` thumbnails are 64×64 and tappable into gallery
7. Calendar day cells are portrait-ratio rounded-rect cards (not circles)
8. Days with 2+ entries or 3+ photos show a stacked deck with count badge
9. App launch without authentication shows `SignInView` with "Sign in with Apple" button
10. After Sign in with Apple, user reaches `ContentView` and data syncs under authenticated identity
11. Settings shows Account section (name, sign out) and Habit Templates header has pencil.circle icon
12. `EditButton` is removed from the Settings toolbar
13. All tests pass

---

## Risks / Unknowns

1. **AWS Cognito Identity Pool config required** — the pool must have `appleid.apple.com` added as a federated provider in the AWS console before `authenticateWithApple` will work. This is a manual AWS step outside of code.
2. **IAM authenticated role** — the Cognito pool's authenticated IAM role must have the same DynamoDB + S3 + API Gateway permissions as the current unauthenticated role. Needs AWS console verification.
3. **Sign in with Apple on Simulator** — requires a real Apple ID logged into the simulator and a provisioned App ID with "Sign in with Apple" capability. Test on device for full flow.
4. **Data migration scope** — if user was previously using the app anonymously and signs in on a new device, their anonymous DynamoDB data won't be under the authenticated IdentityId. Local SwiftData data will re-sync correctly. Cross-device anonymous → authenticated migration is deferred to a follow-up.
5. **`SignInWithAppleButton` requires AuthenticationServices** — framework auto-links on iOS 17, no `project.yml` change needed.
6. **Entitlement** — `com.apple.developer.applesignin` must match an App ID in the Apple Developer portal. Simulator testing may work without a valid provisioning profile; device testing requires it.
