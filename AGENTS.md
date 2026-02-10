# AGENTS.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

NBreader is a pure Dart/Flutter ebook reading engine, ported from an Android Kotlin/C++ app (original source in `NBReader-master/`). It supports **TXT**, **EPUB**, and **Markdown** formats with full typesetting, pagination, page-turn animations, and reading configuration.

The primary language for code comments, UI strings, and documentation is **Chinese (zh)**. All code identifiers and APIs use English.

## Build & Run Commands

```
# Install dependencies
flutter pub get

# Run the app
flutter run

# Static analysis (uses flutter_lints)
flutter analyze

# Run tests
flutter test

# Run a single test file
flutter test test/widget_test.dart
```

Target platforms: Android, iOS, macOS, Linux, Web, Windows. SDK constraint: `^3.9.2`.

## Architecture

The codebase follows a layered architecture with three core layers and one replaceable business layer:

### Layer 1: Parser (`lib/parser/`)
Format plugins that implement `FormatPlugin` (in `parser/format_plugin.dart`). Each plugin reads a file format and emits a stream of `TextTag` objects (content, control, paragraph, image tags).

- **TxtPlugin** — TXT files with auto encoding detection (UTF-8/GBK/GB2312/Big5), chapter detection via regex, CJK-aware paragraph breaking
- **EpubPlugin** — EPUB files via OPF/NCX/XHTML parsing (uses `archive` for ZIP, `xml` for XML). Supports embedded images via `ImageDataResolver`
- **MarkdownPlugin** — Markdown files with heading-based chapter splitting, code highlighting, table rendering, local image loading

EPUB parsing pipeline: `container.xml` → `ContainerReader` → OPF path → `OpfReader` (manifest/spine/metadata) → `NcxReader` (TOC) → `XhtmlContentReader` (chapter XHTML → TextTags).

### Layer 2: Text Engine (`lib/text/`)
The typesetting and pagination engine, responsible for breaking text into pages and rendering them.

- **TextModel** (`engine/text_model.dart`) — Wraps a `FormatPlugin`, manages chapters, provides `TextChapterCursor` with LRU cache (5 chapters)
- **Cursor hierarchy** — `TextChapterCursor` → `TextParagraphCursor` → `TextWordCursor`. Cursors decode `TextTag` streams into `TextElement` arrays (words, control marks, images, spaces) with CJK character-level splitting
- **TextEngine** (`engine/text_engine.dart`) — Core pagination algorithm. Given a viewport size, finds page boundaries using `findPageEndCursor()`, then lays out lines via `prepareTextLine()`. Extends `BaseTextEngine` for style/metrics management
- **TextPageController** (`engine/text_page_controller.dart`) — Manages current/prev/next page state, chapter transitions, and position-based navigation
- **TextCanvas** (`engine/text_canvas.dart`) — Draws prepared pages onto Flutter `Canvas` using `TextElementArea` coordinates

Key data flow: `FormatPlugin` → `TextTag[]` → `TextModel` → `TextChapterCursor` → `TextParagraphCursor` (decodes tags into `TextElement[]`) → `TextEngine` (paginates into `TextPage[]`) → `TextCanvas` (renders)

### Layer 3: Widget (`lib/widget/`)
- **TextReaderWidget** — The main reader widget. Integrates `TextEngine` + `PageAnimation` + gesture handling. Provides API for page turning, chapter jumping, config updates, and progress save/restore via `TextFixedPosition`
- **Page animations** (`widget/anim/`) — 5 types: none, slide, cover, simulation (curl), scroll. All implement `PageAnimation` abstract class

### Business Layer (`lib/core/`, `lib/data/`, `lib/ui/`) — Replaceable
- `BookEntity` / `BookType` — Domain models. `BookType` supports `.txt`, `.epub`, `.md`
- `BookRepository` — SharedPreferences-based persistence (bookshelf + reading progress)
- `BookshelfPage` / `ReadPage` / `ReadMenu` / `CatalogDrawer` — Sample UI. `ReadPage` orchestrates plugin creation, model setup, config management, progress save/restore, and immersive mode

## Key Patterns

- **TextFixedPosition** (paragraph + element + char index) is used for precise reading position that survives config changes (font size, margins, etc). Always prefer this over page-index-based positions.
- **`updateTextConfig()`** on the reader widget triggers automatic repagination with position recovery — no manual refresh needed.
- **TextReaderWidget must have explicit size constraints** (e.g. inside `Expanded`). The engine needs viewport dimensions for pagination.
- **`plugin.release()`** must be called when done to free file caches and memory.
- **`main.dart`** contains both the production app entry point (`NBReaderApp`) and phase-by-phase test apps (Phase 1–6) that were used during incremental development. The phase test classes use inline mock plugins.
- CJK text is auto-detected and uses per-character line breaking (`breakParagraphAtNewLine`).
- EPUB images are decoded asynchronously; first render shows a placeholder, then re-paginates when decoded.

## Dependencies

- `archive` — EPUB ZIP extraction
- `xml` — XHTML/OPF/NCX parsing
- `file_picker` — Book import
- `shared_preferences` — Bookshelf/progress persistence
- `markdown` — Markdown AST parsing
- `http` — Network image fetching (markdown)
