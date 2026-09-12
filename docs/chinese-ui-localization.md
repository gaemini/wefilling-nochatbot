# Simplified Chinese UI

## Scope

- UI languages: 한국어 / English / 简体中文.
- Selected Chinese preference: `app_language = zh_Hans`.
- Flutter locale: `Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans')`.
- `app_zh.arb` contains all 1,013 existing message keys. The `zh` base catalog is
  Simplified Chinese and is used for the explicitly supported `zh_Hans` locale.
- Existing Korean/English ARB files and generated Korean/English translations
  are unchanged. Future missing-key handling remains Flutter's existing fallback.
- Existing inline Korean/English UI strings retain their original branches;
  Chinese branches were added to the same display sites. This is not a runtime
  replacement of arbitrary text, user posts, messages or other user content.
- Profile tags and country names have Chinese display labels. Stored IDs,
  nationality values, nickname validation and signup policies are unchanged.

## Fonts and layout

- Noto Sans SC is bundled with its OFL license (about 17 MiB); no network font
  loading is required. Regular/Medium/SemiBold/Bold are registered.
- `ui_locale.dart` and the Chinese-only theme select `NotoSansSC`. Korean/English
  keep their original fonts, sizes and weights.
- Chinese text uses additional line height where the original height was too
  tight. Bottom-navigation height accounts for the Chinese line height.
- The language selector supports three rows. Its bottom sheet has a bounded,
  scrollable layout so the extra row fits small screens without shrinking text.
- Async notifications use a live messenger context or capture the Chinese
  locale before awaiting, avoiding new lookups through a disposed screen.

## Unchanged systems

Firestore rules, collections, Cloud Functions, authentication providers, signup
flows, API implementations, DM/chat delivery and content-translation algorithms
were not changed. `navigation_service.dart` only changes the text/font of its
embedded “cannot join room” screen; routing is unchanged.

This is UI localization, not a server notification/content migration. Remote
push notifications, administrator-authored semester content, existing user
content, native permission messages and server-generated summaries retain their
existing language/fallback policies. The existing content-translation service
already recognizes `zh`; its automatic/manual target-selection policy remains
unchanged.

## Verification

- `flutter gen-l10n`: succeeds, no missing Chinese messages.
- 101 tests passed across the Chinese UI test and 17 existing related test files.
- Chinese tests load the actual bundled font and cover locale persistence,
  all ARB keys/placeholders, Korean/English font preservation, country/tag labels,
  320/360/430px navigation, profile inputs, translation settings, polls, recap,
  login language choices, Meetup cards, attachments, SnackBar and language picker.
- Login and language-picker screenshots were visually inspected at 320px.
- `flutter analyze --no-pub`: no errors. The repository still reports lint and
  warning diagnostics; this task does not perform a global lint cleanup.
- `git diff --check` and iOS plist validation pass.
- The complete test suite is not green: Firebase setup failures, stale fixture
  expectations and a snapshot-letter timeout also reproduce on the unmodified
  HEAD in an isolated directory. One transient test-runner crash was rerun
  separately and passed. Unrelated tests were not modified to hide those failures.

Run the focused Chinese checks with:

```sh
flutter gen-l10n
flutter test test/chinese_ui_localization_test.dart
```

Optional visual captures are written under `/tmp/wefilling-zh-*.png`:

```sh
flutter test test/chinese_ui_localization_test.dart --dart-define=CAPTURE_ZH_UI=true
```

Before release, perform signed-in device smoke tests for post creation, Meetup,
SnackChat and DM, including keyboard-open and landscape layouts. No production
accounts, backend deployments or real messages were used during these tests.

## Logout lifecycle and Chinese login follow-up

- Reproduced the reported `Looking up a deactivated widget's ancestor is unsafe`
  error: logout's AnimatedBuilder was resolving the Chinese font through the
  opening page's context after authentication replaced that page.
- Logout typography now uses the live dialog builder context. Navigator states
  are obtained before awaiting sign-out; existing authentication and navigation
  decisions are preserved. The error is not suppressed or hidden.
- Chinese login displays `KOR / ENG / 简体中文`. Its language choices occupy real
  layout space, wrap when necessary and cannot overlap the logo/content.
- Only the Chinese login presentation changes: white background, no card shadow,
  neutral heading, consistent padding and bounded content width. Korean/English
  retain their previous background and overlaid language-control layout.
- Chinese logout content can scroll on short screens. SafeArea continues to
  protect the Android navigation area; global font sizes were not reduced.
- 31 related tests pass, including removal of the opening page during logout,
  removal of the dialog before completion, unchanged ko/en logout navigation,
  320/360/390/430px portrait and 568px landscape, 1.3x/2x text scaling, and simulated
  Android top/bottom system insets. The Chinese login capture was visually checked.

```sh
flutter test test/chinese_logout_lifecycle_test.dart test/chinese_ui_localization_test.dart
```
