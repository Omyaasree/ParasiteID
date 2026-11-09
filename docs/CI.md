# Continuous Integration (iOS)

Workflow: `.github/workflows/ios-ci.yml` (GitHub Actions, macOS runner).

## When it runs
- On every pull request that touches `ios/**` (or the workflow file)
- On pushes to `main`
- Manually: GitHub → Actions → "iOS CI" → *Run workflow*

## What it does
1. **Build** the `ParasiteIDApp` scheme for the iOS Simulator (no code signing).
2. **Test**: runs `xcodebuild test` *if* the project has a unit/UI test target. Until one exists this step is skipped with a notice (not a failure).
3. Uploads `build.log`, `test.log`, and `TestResults.xcresult` as the `ios-ci-logs` artifact.

## Reading the results
On a PR, see the **Checks** section at the bottom.
- ✅ green: it builds (and tests pass, if any exist).
- ❌ red: click **Details**, open the failing step, and search for `error:` (compile errors) or `Test Case ... failed` (test failures).
- "No test target yet" notice: expected for now.
- Download the `ios-ci-logs` artifact for full logs; open `TestResults.xcresult` in Xcode for per-test detail.

## Run the same checks locally
```sh
cd ios
xcodebuild build -project ParasiteIDApp.xcodeproj -scheme ParasiteIDApp \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
# once tests exist:
xcodebuild test -project ParasiteIDApp.xcodeproj -scheme ParasiteIDApp \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```
(Use any simulator name from `xcrun simctl list devices available`.)

## Adding tests
In Xcode: File → New → Target → *Unit Testing Bundle*, name it `ParasiteIDAppTests`, then make sure it's checked under Product → Scheme → Edit Scheme → Test. Commit the `.pbxproj` and shared scheme; CI will pick it up automatically.

## Recommended repo settings
Settings → Branches → protect `main` → require the **iOS CI / build-and-test** check to pass before merging.

## Known caveats
- The project's deployment target is iOS 27.0; the runner's Xcode must support it. If the build fails with an SDK/deployment-target error, either lower the target in Xcode or pin a newer Xcode with a `sudo xcode-select -s` step.
- The scheme is shared (`ios/ParasiteIDApp.xcodeproj/xcshareddata`) so CI can find it. Don't delete it.
