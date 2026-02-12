import '../../element/text_code_block_element.dart';
import '../../element/text_word_element.dart';
import '../../entity/text_position.dart';
import 'text_paragraph_cursor.dart';

/// 单词光标 - 精确定位到文本中的任意位置
/// 移植自 Kotlin TextWordCursor
class TextWordCursor extends TextPosition {
  late TextParagraphCursor _paragraphCursor;
  int _elementIndex = 0;
  int _charIndex = 0;

  /// 从段落光标创建
  TextWordCursor(TextParagraphCursor paragraphCursor) {
    _paragraphCursor = paragraphCursor;
    _elementIndex = 0;
    _charIndex = 0;
  }

  /// 复制构造
  TextWordCursor.copy(TextWordCursor other) {
    _paragraphCursor = other._paragraphCursor;
    _elementIndex = other._elementIndex;
    _charIndex = other._charIndex;
  }

  /// 更新光标（从另一个 WordCursor）
  void updateCursor(TextWordCursor other) {
    _paragraphCursor = other._paragraphCursor;
    _elementIndex = other._elementIndex;
    _charIndex = other._charIndex;
  }

  /// 更新光标（从段落光标）
  void updateFromParagraph(TextParagraphCursor paragraphCursor) {
    _paragraphCursor = paragraphCursor;
    _elementIndex = 0;
    _charIndex = 0;
  }

  /// 获取段落光标
  TextParagraphCursor getParagraphCursor() => _paragraphCursor;

  // === TextPosition 实现 ===

  @override
  int get chapterIndex => _paragraphCursor.chapterIndex;

  @override
  int get paragraphIndex => _paragraphCursor.paragraphIndex;

  @override
  int get elementIndex => _elementIndex;

  @override
  int get charIndex => _charIndex;

  // === 移动操作 ===

  /// 移动到下一个单词
  void moveToNextWord() {
    _elementIndex++;
    _charIndex = 0;
  }

  /// 移动到上一个单词
  void moveToPrevWord() {
    _elementIndex--;
    _charIndex = 0;
  }

  /// 移动到下一段落开头
  bool moveToNextParagraph() {
    if (_paragraphCursor.isLastOfText()) return false;
    final next = _paragraphCursor.nextCursor();
    if (next == null) return false;
    _paragraphCursor = next;
    moveToParagraphStart();
    return true;
  }

  /// 移动到上一段落开头
  bool moveToPrevParagraph() {
    if (_paragraphCursor.isFirstOfText()) return false;
    final prev = _paragraphCursor.prevCursor();
    if (prev == null) return false;
    _paragraphCursor = prev;
    moveToParagraphStart();
    return true;
  }

  /// 移动到指定位置
  void moveTo(int elementIdx, [int charIdx = 0]) {
    if (elementIdx == 0 && charIdx == 0) {
      _elementIndex = 0;
      _charIndex = 0;
    } else {
      var idx = elementIdx < 0 ? 0 : elementIdx;
      final count = _paragraphCursor.getElementCount();

      if (idx >= count) {
        _elementIndex = count;
        _charIndex = 0;
      } else {
        _elementIndex = idx;
        moveToCharIndex(charIdx);
      }
    }
  }

  /// 移动到当前元素的字符位置
  /// 对于 TextWordElement，charIndex 是字符偏移；
  /// 对于 TextCodeBlockElement，charIndex 是起始行号。
  void moveToCharIndex(int charIdx) {
    var idx = charIdx < 0 ? 0 : charIdx;
    _charIndex = 0;

    if (idx > 0) {
      final element = _paragraphCursor.getElement(_elementIndex);
      if (element is TextWordElement) {
        if (idx <= element.length) {
          _charIndex = idx;
        }
      } else if (element is TextCodeBlockElement) {
        // 代码块：charIndex 表示从第几行开始渲染
        if (idx < element.lines.length) {
          _charIndex = idx;
        }
      }
    }
  }

  /// 是否在段落开头
  bool isStartOfParagraph() => _elementIndex == 0 && _charIndex == 0;

  /// 是否在全文开头
  bool isStartOfText() =>
      isStartOfParagraph() && _paragraphCursor.isFirstOfText();

  /// 是否在段落末尾
  bool isEndOfParagraph() =>
      _elementIndex == _paragraphCursor.getElementCount();

  /// 是否在全文末尾
  bool isEndOfText() =>
      isEndOfParagraph() && _paragraphCursor.isLastOfText();

  /// 移动到段落开头
  void moveToParagraphStart() {
    _elementIndex = 0;
    _charIndex = 0;
  }

  /// 移动到段落末尾
  void moveToParagraphEnd() {
    _elementIndex = _paragraphCursor.getElementCount();
    _charIndex = 0;
  }

  @override
  String toString() =>
      'TextWordCursor(ch=$chapterIndex, para=$paragraphIndex, elem=$_elementIndex, char=$_charIndex)';
}
