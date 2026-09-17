# Flutter UI architecture

The desktop UI follows Material Design 3 with an FPT-inspired orange and white palette. This is a project theme, not an official FPT design system.

## File responsibilities

- `lib/core/theme/app_palette.dart`: shared brand colors, neutral surfaces and borders.
- `lib/core/app_theme.dart`: Material component themes, typography, inputs, buttons and navigation.
- `lib/shared/widgets/`: reusable presentation widgets across features, including `SectionHeader`.
- `lib/features/<feature>/`: screens and feature-specific interaction state.
- `lib/features/<feature>/widgets/`: reusable parts and form definitions belonging to a feature.
- `lib/models/`: typed records and domain validation.
- `lib/repositories/`: data operations and demo implementations.
- `lib/services/`: HTTP, OAuth, OCR and file parsing integrations.

Keep API calls in repositories/services. Screens consume typed models. Reuse the theme and palette instead of adding separate brand colors to individual screens. Green and red remain meaningful success/error colors. Course colors distinguish timetable entries.

## Visual conventions

White cards on a warm off-white canvas, pale orange section headers, orange primary actions, dark readable text, 12 px input/button corners and 20–24 px card/header corners. Use Segoe UI on Windows with platform fallback elsewhere. Preserve horizontal scrolling for the timetable and wrapping for form groups.

## OCR review

The semester is required before image selection, parsing, manual row insertion and saving. Changing it invalidates the reviewed state and requires parsing again. It fills rows where OCR did not identify a semester; detected semesters remain visible for review.

NVH missing-time completion is enabled by default. Explicit OCR times remain unchanged. The review hides the subject-name input; a detected name is retained, otherwise the subject code is used as a fallback to preserve the existing backend schema. Manual schedule editing still exposes the subject name.

## Verification

`flutter analyze lib`

`flutter test test/ocr_save_test.dart test/widget_test.dart test/attendance_qr_test.dart test/roster_ui_test.dart`

The visual test can capture previews on Windows with `CAPTURE_UI=1`; generated images are written under `build/ui-review/` and are not source assets.
