import '../../element/text_code_block_element.dart';
import '../../element/text_control_element.dart';
import '../../element/text_element.dart';
import '../../element/text_fixed_hspace_element.dart';
import '../../element/text_horizontal_rule_element.dart';
import '../../element/text_image_element.dart';
import '../../element/text_style_element.dart';
import '../../element/text_table_element.dart';
import '../../element/text_word_element.dart';
import '../../entity/text_paragraph.dart';
import '../../entity/text_position.dart';
import '../../tag/text_tag.dart';
import '../../tag/text_tag_type.dart';
import '../../util/line_breaker.dart';
import 'text_chapter_cursor.dart';

/// 段落光标 - 管理段落内的 Element 列表
/// 移植自 Kotlin TextParagraphCursor
class TextParagraphCursor extends TextPosition {
  final TextChapterCursor _chapterCursor;
  final int _paragraphIndex;
  final TextParagraph _paragraph;
  final List<TextElement> _elements;

  TextParagraphCursor(this._chapterCursor, this._paragraphIndex)
      : _paragraph = _chapterCursor.getParagraph(_paragraphIndex),
        _elements = _ParagraphContentDecoder(
          _chapterCursor.getParagraph(_paragraphIndex),
          _chapterCursor.getParagraphContent(_paragraphIndex),
          _chapterCursor.getLanguage(),
        ).decode();

  /// 获取章节光标
  TextChapterCursor getChapterCursor() => _chapterCursor;

  /// 获取段落信息
  TextParagraph getParagraph() => _paragraph;

  /// 获取元素
  TextElement? getElement(int index) {
    if (index < 0 || index >= _elements.length) return null;
    return _elements[index];
  }

  /// 获取元素总数
  int getElementCount() => _elements.length;

  /// 是否章节第一段
  bool isFirstOfChapter() => _paragraphIndex == 0;

  /// 是否全书第一段
  bool isFirstOfText() => _chapterCursor.isFirstChapter() && isFirstOfChapter();

  /// 是否章节最后一段
  bool isLastOfChapter() =>
      _paragraphIndex == _chapterCursor.getParagraphCount() - 1;

  /// 是否全书最后一段
  bool isLastOfText() => _chapterCursor.isLastChapter() && isLastOfChapter();

  /// 是否是分节结束段落
  bool isEndOfSection() =>
      _paragraph.type == TextParagraphType.endOfSectionParagraph;

  /// 上一段光标
  TextParagraphCursor? prevCursor() {
    if (isFirstOfText()) return null;
    if (isFirstOfChapter()) {
      final prevChapter = _chapterCursor.prevCursor()!;
      return prevChapter.getParagraphCursor(prevChapter.getParagraphCount() - 1);
    }
    return _chapterCursor.getParagraphCursor(_paragraphIndex - 1);
  }

  /// 下一段光标
  TextParagraphCursor? nextCursor() {
    if (isLastOfText()) return null;
    if (isLastOfChapter()) {
      final nextChapter = _chapterCursor.nextCursor()!;
      return nextChapter.getParagraphCursor(0);
    }
    return _chapterCursor.getParagraphCursor(_paragraphIndex + 1);
  }

  // === TextPosition 实现 ===

  @override
  int get chapterIndex => _chapterCursor.chapterIndex;

  @override
  int get paragraphIndex => _paragraphIndex;

  @override
  int get elementIndex => 0;

  @override
  int get charIndex => 0;
}

/// 段落内容解码器 - 将 TextTag 序列解码为 TextElement 列表
/// 移植自 Kotlin ParagraphContentDecoder
class _ParagraphContentDecoder {
  static const int _noSpace = 0;
  static const int _space = 1;
  static const int _nonBreakableSpace = 2;

  /// 断行缓冲区
  static List<int> _breakCache = List<int>.filled(1024, 0);

  final TextParagraph _paragraph;
  final TextTagIterator _tagIterator;
  final String _language;

  _ParagraphContentDecoder(this._paragraph, this._tagIterator, this._language);

  List<TextElement> decode() {
    final elements = <TextElement>[];

    switch (_paragraph.type) {
      case TextParagraphType.textParagraph:
        _processTextParagraph(elements);
        break;
      case TextParagraphType.emptyLineParagraph:
        // 空行段落，不处理
        break;
      default:
        break;
    }

    return elements;
  }

  void _processTextParagraph(List<TextElement> elements) {
    while (_tagIterator.hasNext()) {
      final tag = _tagIterator.next();

      if (tag is TextContentTag) {
        _processContentTag(tag, elements);
      } else if (tag is TextControlTag) {
        elements.add(TextControlElement(tag.type, tag.isStart));
      } else if (tag is TextCssStyleTag || tag is TextOtherStyleTag) {
        elements.add(TextStyleElement(tag));
      } else if (tag is TextStyleCloseTag) {
        elements.add(TextElement.styleClose);
      } else if (tag is TextFixedHSpaceTag) {
        elements.add(TextFixedHSpaceElement.getElement(tag.length));
      } else if (tag is TextImageTag) {
        elements.add(TextImageElement(
          TextImage(id: tag.id, filePath: tag.id, data: tag.imageData),
        ));
      } else if (tag is TextHorizontalRuleTag) {
        elements.add(const TextHorizontalRuleElement());
      } else if (tag is TextCodeBlockTag) {
        elements.add(TextCodeBlockElement(
          language: tag.language,
          lines: tag.lines,
        ));
      } else if (tag is TextTableTag) {
        elements.add(TextTableElement(
          headers: tag.headers,
          rows: tag.rows,
          alignments: tag.alignments,
        ));
      } else if (tag is TextBlockquoteStartTag) {
        // 引用块通过 ControlType.blockquote 处理样式
        elements.add(TextControlElement(TextControlType.blockquote, true));
      } else if (tag is TextBlockquoteEndTag) {
        elements.add(TextControlElement(TextControlType.blockquote, false));
      } else if (tag is TextLinkStartTag || tag is TextLinkEndTag) {
        // 链接标签在 ControlTag 中已处理（link ControlType）
      }
    }
  }

  /// 处理文本内容标签 → 拆分为 TextWordElement + 空格
  void _processContentTag(TextContentTag tag, List<TextElement> elements) {
    final content = tag.content;
    if (content.isEmpty) return;

    final contentCodes = content.codeUnits;
    final contentLen = contentCodes.length;

    // 确保断行缓冲区足够大
    if (_breakCache.length < contentLen) {
      _breakCache = List<int>.filled(contentLen, 0);
    }

    // 计算断行点
    LineBreaker.setLineBreak(contentCodes, 0, contentLen, _language, _breakCache);

    int spaceState = _noSpace;
    int wordStart = 0;
    int previousChar = 0;
    int ch = 0;

    for (int i = 0; i < contentLen; i++) {
      previousChar = ch;
      ch = contentCodes[i];

      if (_isWhitespace(ch)) {
        // 空白字符
        if (i > 0 && spaceState == _noSpace) {
          _addWord(contentCodes, wordStart, i - wordStart, elements);
        }
        spaceState = _space;
      } else if (_isSpaceChar(ch)) {
        // 不间断空格类
        if (i > 0 && spaceState == _noSpace) {
          _addWord(contentCodes, wordStart, i - wordStart, elements);
        }
        elements.add(TextElement.nbSpace);
        if (spaceState != _space) {
          spaceState = _nonBreakableSpace;
        }
      } else {
        // 普通字符
        switch (spaceState) {
          case _space:
            elements.add(TextElement.hSpace);
            wordStart = i;
            break;
          case _nonBreakableSpace:
            wordStart = i;
            break;
          case _noSpace:
            if (i > 0 &&
                _breakCache[i - 1] != LineBreaker.nobreak &&
                previousChar != 0x2D && // '-'
                i != wordStart) {
              _addWord(contentCodes, wordStart, i - wordStart, elements);
              wordStart = i;
            }
            break;
        }
        spaceState = _noSpace;
      }
    }

    // 处理最后的字符
    switch (spaceState) {
      case _space:
        elements.add(TextElement.hSpace);
        break;
      case _nonBreakableSpace:
        elements.add(TextElement.nbSpace);
        break;
      case _noSpace:
        _addWord(contentCodes, wordStart, contentLen - wordStart, elements);
        break;
    }
  }

  void _addWord(List<int> data, int offset, int length, List<TextElement> elements) {
    if (length <= 0) return;
    elements.add(TextWordElement(data, offset, length));
  }

  static bool _isWhitespace(int ch) {
    return ch == 0x20 || ch == 0x09 || ch == 0x0A || ch == 0x0D || ch == 0x0B;
  }

  static bool _isSpaceChar(int ch) {
    return ch == 0xA0; // non-breaking space
  }
}
