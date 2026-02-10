import '../engine/cursor/text_word_cursor.dart';
import 'text_line.dart';
import 'text_element_area.dart';

/// 文本页面
/// 移植自 Kotlin TextPage
class TextPage {
  /// 页面起始光标（快照）
  final TextWordCursor startWordCursor;

  /// 页面结束光标（快照）
  final TextWordCursor endWordCursor;

  /// 文本行列表
  final List<TextLine> textLineList = [];

  /// 元素绘制区域向量
  final TextElementAreaVector textElementAreaVector = TextElementAreaVector();

  /// 是否已经准备好（行列表已计算）
  bool isPrepare = false;

  TextPage(TextWordCursor startCursor, TextWordCursor endCursor)
      : startWordCursor = TextWordCursor.copy(startCursor),
        endWordCursor = TextWordCursor.copy(endCursor);

  /// 重置页面（释放缓存）
  void reset() {
    textLineList.clear();
    textElementAreaVector.clear();
    isPrepare = false;
  }

  @override
  String toString() => 'TextPage(isPrepare=$isPrepare, lines=${textLineList.length})';
}
