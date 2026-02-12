import 'package:flutter_test/flutter_test.dart';

import 'package:nbreader/parser/format_plugin.dart';
import 'package:nbreader/text/annotation/text_annotation.dart';
import 'package:nbreader/text/config/text_config.dart';
import 'package:nbreader/text/engine/text_engine.dart';
import 'package:nbreader/text/engine/text_model.dart';
import 'package:nbreader/text/entity/text_chapter.dart';
import 'package:nbreader/text/entity/text_content.dart';
import 'package:nbreader/text/entity/text_position.dart';
import 'package:nbreader/text/tag/text_tag.dart';
import 'package:nbreader/text/tag/text_tag_type.dart';

class _FakePlugin implements FormatPlugin {
  final List<TextChapter> _chapters;
  final Map<String, TextContent> _contents;

  _FakePlugin(this._chapters, this._contents);

  @override
  Future<void> openBook(String bookPath) async {}

  @override
  String getEncoding() => 'utf-8';

  @override
  String getLanguage() => 'en';

  @override
  List<TextChapter> getChapters() => _chapters;

  @override
  TextContent? getChapterContent(TextChapter chapter) => _contents[chapter.url];

  @override
  String? getChapterPlainText(TextChapter chapter) =>
      _contents[chapter.url]?.toPlainText();

  @override
  ImageDataResolver? get imageDataResolver => null;

  @override
  void release() {}
}

void main() {
  group('TextAnnotation', () {
    test('json roundtrip + normalizeRange', () {
      final a = TextFixedPosition(
        chapterIndex: 0,
        paragraphIndex: 1,
        elementIndex: 2,
        charIndex: 3,
      );
      final b = TextFixedPosition(
        chapterIndex: 0,
        paragraphIndex: 0,
        elementIndex: 0,
        charIndex: 0,
      );

      // 故意 start > end
      final ann = TextAnnotation(
        id: '1',
        kind: TextAnnotationKind.highlight,
        start: a,
        end: b,
        style: const TextAnnotationStyle(
          type: TextAnnotationStyleType.background,
          color: 0xFF00FF00,
        ),
        createdAt: 1,
        updatedAt: 2,
      );

      final json = ann.toJson();
      final decoded = TextAnnotation.fromJson(json);

      expect(decoded.kind, TextAnnotationKind.highlight);
      expect(decoded.style.type, TextAnnotationStyleType.background);
      expect(decoded.style.color, 0xFF00FF00);

      // fromJson 会自动 normalized
      expect(decoded.start.compareTo(decoded.end) <= 0, isTrue);
      expect(decoded.start.chapterIndex, 0);
      expect(decoded.start.paragraphIndex, 0);
      expect(decoded.end.paragraphIndex, 1);
    });
  });

  group('TextEngine.extractText', () {
    late TextEngine engine;

    setUp(() {
      final chapters = <TextChapter>[
        const TextChapter(url: 'c1', title: 'c1', startIndex: 0, endIndex: -1),
        const TextChapter(url: 'c2', title: 'c2', startIndex: 0, endIndex: -1),
      ];

      final contents = <String, TextContent>{
        'c1': TextContent(
          tags: const [
            TextParagraphTag(TextParagraphType.textParagraph),
            TextContentTag('Hello world'),
            TextParagraphTag(TextParagraphType.textParagraph),
            TextContentTag('Second line'),
            TextParagraphTag(TextParagraphType.endOfSectionParagraph),
          ],
        ),
        'c2': TextContent(
          tags: const [
            TextParagraphTag(TextParagraphType.textParagraph),
            TextContentTag('Third'),
            TextParagraphTag(TextParagraphType.endOfSectionParagraph),
          ],
        ),
      };

      final model = TextModel(_FakePlugin(chapters, contents));
      engine = TextEngine(TextConfig());
      engine.init(model);
    });

    test('right-open range within a word', () {
      final start = TextFixedPosition(
        chapterIndex: 0,
        paragraphIndex: 0,
        elementIndex: 0,
        charIndex: 0,
      );
      final end = TextFixedPosition(
        chapterIndex: 0,
        paragraphIndex: 0,
        elementIndex: 0,
        charIndex: 5,
      );

      expect(engine.extractText(start, end), 'Hello');
    });

    test('partial slice within a word', () {
      final start = TextFixedPosition(
        chapterIndex: 0,
        paragraphIndex: 0,
        elementIndex: 0,
        charIndex: 1,
      );
      final end = TextFixedPosition(
        chapterIndex: 0,
        paragraphIndex: 0,
        elementIndex: 0,
        charIndex: 4,
      );

      expect(engine.extractText(start, end), 'ell');
    });

    test('preserves spaces between words', () {
      final start = TextFixedPosition(
        chapterIndex: 0,
        paragraphIndex: 0,
        elementIndex: 0,
        charIndex: 0,
      );
      final end = TextFixedPosition(
        chapterIndex: 0,
        paragraphIndex: 0,
        elementIndex: 2,
        charIndex: 5,
      );

      expect(engine.extractText(start, end), 'Hello world');
    });

    test('adds newline between paragraphs', () {
      final start = TextFixedPosition(
        chapterIndex: 0,
        paragraphIndex: 0,
        elementIndex: 0,
        charIndex: 0,
      );
      final end = TextFixedPosition(
        chapterIndex: 0,
        paragraphIndex: 1,
        elementIndex: 2,
        charIndex: 4,
      );

      expect(engine.extractText(start, end), 'Hello world\nSecond line');
    });

    test('adds a single newline between chapters', () {
      final start = TextFixedPosition(
        chapterIndex: 0,
        paragraphIndex: 1,
        elementIndex: 0,
        charIndex: 0,
      );
      final end = TextFixedPosition(
        chapterIndex: 1,
        paragraphIndex: 0,
        elementIndex: 0,
        charIndex: 5,
      );

      expect(engine.extractText(start, end), 'Second line\nThird');
    });

    test('empty range returns empty string', () {
      final pos = TextFixedPosition(
        chapterIndex: 0,
        paragraphIndex: 0,
        elementIndex: 0,
        charIndex: 0,
      );

      expect(engine.extractText(pos, pos), '');
    });
  });
}
