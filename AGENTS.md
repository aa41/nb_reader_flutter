# AGENTS.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

NBreader is a Flutter e-book reader supporting TXT and EPUB formats. It was ported from Android NBReader (Kotlin/C++). The codebase is primarily in Chinese with some English comments.

Key capabilities:
- TXT parsing with auto-encoding detection and CJK text optimization
- EPUB parsing (OPF/NCX/XHTML, embedded images)
- Text layout engine with pagination and style inheritance
- 5 page turn animations (none, slide, cover, simulation, scroll)
- Reading settings (font size, line spacing, letter spacing, margins, night mode)
- Reading progress save/restore

## Build and Development Commands

```bash
# Install dependencies
flutter pub get

# Run the app (defaults to connected device/emulator)
flutter run

# Run on specific platform
flutter run -d macos
flutter run -d chrome

# Run tests
flutter test

# Run a single test
flutter test test/widget_test.dart

# Analyze code (linting)
flutter analyze

# Build release
flutter build macos
flutter build apk
```

## Architecture

```
lib/
├── parser/                    # Format parsing layer
│   ├── format_plugin.dart     # Plugin interface (FormatPlugin)
│   ├── txt/                   # TXT parsing (TxtPlugin, TxtReader)
│   ├── epub/                  # EPUB parsing (EpubPlugin, XhtmlContentReader)
│   └── encoding/              # Encoding detection
├── text/                      # Rendering engine layer
│   ├── config/text_config.dart      # Reading configuration
│   ├── style/tree_text_style.dart   # Hierarchical text styles
│   ├── engine/
│   │   ├── text_engine.dart         # Core layout/pagination engine
│   │   ├── text_model.dart          # Data model (chapter loading, LRU cache)
│   │   ├── text_page_controller.dart # Page navigation
│   │   └── cursor/                  # Word/paragraph cursors for traversal
│   ├── element/               # Inline elements (words, images, spaces)
│   ├── entity/                # Data entities (pages, lines, chapters)
│   └── tag/                   # Tag types for content representation
├── widget/                    # Widget layer
│   ├── text_reader_widget.dart    # Main reader widget (use via GlobalKey)
│   ├── page_enum.dart             # PageType, PageAnimType enums
│   └── anim/                      # Page turn animation implementations
├── core/                      # Business entities (replaceable)
├── data/                      # Data persistence (replaceable)
└── ui/                        # Sample UI (replaceable)
```

**Minimal integration requires:** `parser/`, `text/`, `widget/` directories. The `core/`, `data/`, `ui/` are sample implementations.

## Key Integration Patterns

### Creating a reader
```dart
// 1. Create plugin based on file type
FormatPlugin plugin = filePath.endsWith('.epub') ? EpubPlugin() : TxtPlugin();

// 2. Open book
await plugin.openBook(filePath);

// 3. Create model and use in widget
final model = TextModel(plugin);
TextReaderWidget(textModel: model, ...)
```

### Accessing reader state via GlobalKey
```dart
final _readerKey = GlobalKey<TextReaderWidgetState>();
// Then: _readerKey.currentState?.skipChapter(index)
//       _readerKey.currentState?.updateTextConfig(config)
//       _readerKey.currentState?.getTextPosition()
```

### TextFixedPosition for progress persistence
Use `TextFixedPosition` (paragraph+element+char level) instead of page numbers when saving/restoring progress, as pagination changes with font/margin settings.

## Testing

- Widget tests: `test/widget_test.dart`
- In-code phase tests: `main.dart` contains test apps for each development phase (Phase1TestApp through Phase6TestApp). Uncomment in `main()` to run specific tests.

## Important Notes

- `TextReaderWidget` must have explicit size constraints (use inside `Expanded`, `SizedBox`, etc.)
- EPUB images decode asynchronously; the engine automatically repaginates when done
- Always call `plugin.release()` when done to free resources
- CJK text is auto-detected and uses character-by-character line breaking
