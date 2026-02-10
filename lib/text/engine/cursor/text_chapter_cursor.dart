import '../../entity/text_paragraph.dart';
import '../../tag/text_tag.dart';
import '../text_model.dart';
import 'text_paragraph_cursor.dart';

/// 章节光标 - 管理章节内的段落列表和段落光标缓存
/// 移植自 Kotlin TextChapterCursor
class TextChapterCursor {
  final TextModel textModel;
  final int chapterIndex;

  /// 章节中的段落列表
  final List<TextParagraph> _paragraphs = [];

  /// 章节中的所有标签
  late final List<TextTag> _tags;

  /// 段落光标缓存
  final Map<int, TextParagraphCursor> _paragraphCursorCache = {};

  TextChapterCursor(this.textModel, this.chapterIndex) {
    final textContent = textModel.getChapterContent(chapterIndex);
    if (textContent == null) {
      _tags = [];
      return;
    }

    _tags = textContent.tags;

    // 扫描 tags，找到所有 TextParagraphTag 的位置和类型
    // Dart 解析器将 ParagraphTag 放在段落开头（start-marker 风格），
    // 每个段落从其 ParagraphTag 开始，到下一个 ParagraphTag 之前结束。
    final paragraphIndices = <int>[];
    final paragraphTypes = <int>[];
    for (int i = 0; i < _tags.length; i++) {
      final tag = _tags[i];
      if (tag is TextParagraphTag) {
        paragraphIndices.add(i);
        paragraphTypes.add(tag.type);
      }
    }

    for (int i = 0; i < paragraphIndices.length; i++) {
      final startOffset = paragraphIndices[i];
      final endOffset = (i + 1 < paragraphIndices.length)
          ? paragraphIndices[i + 1]
          : _tags.length;
      _paragraphs.add(TextParagraph(
        type: paragraphTypes[i],
        indexFromChapter: _paragraphs.length,
        startOffset: startOffset,
        endOffset: endOffset,
      ));
    }
  }

  /// 获取章节信息
  get chapter => textModel.getChapter(chapterIndex);

  /// 获取段落总数
  int getParagraphCount() => _paragraphs.length;

  /// 获取段落信息
  TextParagraph getParagraph(int index) {
    if (index < 0 || index >= _paragraphs.length) {
      throw RangeError('paragraph index $index out of range [0, ${_paragraphs.length})');
    }
    return _paragraphs[index];
  }

  /// 获取段落光标（带缓存）
  TextParagraphCursor getParagraphCursor(int index) {
    if (index < 0 || index >= _paragraphs.length) {
      throw RangeError('paragraph index $index out of range [0, ${_paragraphs.length})');
    }

    var cursor = _paragraphCursorCache[index];
    if (cursor == null) {
      cursor = TextParagraphCursor(this, index);
      _paragraphCursorCache[index] = cursor;
    }
    return cursor;
  }

  /// 获取段落内容的 tag 迭代器
  TextTagIterator getParagraphContent(int paragraphIndex) {
    final paragraph = getParagraph(paragraphIndex);
    return TextTagIterator(_tags, paragraph.startOffset, paragraph.endOffset);
  }

  /// 获取语言
  String getLanguage() => textModel.getLanguage();

  /// 上一章光标
  TextChapterCursor? prevCursor() {
    if (chapterIndex <= 0) return null;
    return textModel.getChapterCursor(chapterIndex - 1);
  }

  /// 下一章光标
  TextChapterCursor? nextCursor() {
    if (chapterIndex >= textModel.getChapterCount() - 1) return null;
    return textModel.getChapterCursor(chapterIndex + 1);
  }

  /// 是否第一章
  bool isFirstChapter() => chapterIndex == 0;

  /// 是否最后一章
  bool isLastChapter() => chapterIndex == textModel.getChapterCount() - 1;

  /// 是否有指定方向的章节
  bool hasChapter(bool next) {
    if (next) {
      return chapterIndex + 1 < textModel.getChapterCount();
    } else {
      return chapterIndex - 1 >= 0;
    }
  }
}

/// Tag 迭代器
class TextTagIterator {
  final List<TextTag> _tags;
  final int _endOffset;
  int _curOffset;

  TextTagIterator(this._tags, int startOffset, this._endOffset)
      : _curOffset = startOffset;

  bool hasNext() => _curOffset < _endOffset;

  TextTag next() => _tags[_curOffset++];

  void reset(int startOffset) {
    _curOffset = startOffset;
  }
}
