# Contributing

Thanks for your interest in contributing to Forever Diary.

## Development Setup

1. Fork and clone the repository
2. Follow the [Setup](#setup) instructions in the README
3. Set up the [Whisper server](docs/whisper-server-setup.md) for speech-to-text
4. Create a feature branch: `git checkout -b feat/your-feature`

## Code Standards

- **Swift**: Follow Swift API design guidelines and SwiftLint conventions
- **SwiftUI**: Prefer small, composable views over monolithic view bodies
- **Architecture**: Services handle business logic, Views handle presentation
- **Models**: SwiftData `@Model` classes live in `ForeverDiary/Models/`

Run tests before committing:

```bash
xcodebuild test \
  -scheme ForeverDiary \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(speech): add WhisperKit on-device engine
fix(sync): resolve batch upload timeout on large entries
refactor(views): extract calendar grid into reusable component
```

## Pull Requests

- Keep PRs focused on a single change
- Include tests for new features and bug fixes
- Update documentation if behavior changes
- All tests must pass before merging
