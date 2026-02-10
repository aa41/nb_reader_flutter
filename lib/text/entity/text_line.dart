import 'dart:math';

import '../engine/cursor/text_paragraph_cursor.dart';
import '../style/tree_text_style.dart';

/// 文本行信息
/// 移植自 Kotlin TextLine
class TextLine {
  /// 所属段落光标
  final TextParagraphCursor paragraphCursor;

  /// 段落元素总数
  final int elementCount;

  /// 行起始元素索引
  int startElementIndex;
  int startCharIndex;

  /// 实际起始元素索引（跳过行首样式元素后）
  int realStartElementIndex;
  int realStartCharIndex;

  /// 行结束元素索引
  int endElementIndex;
  int endCharIndex;

  /// 起始样式
  TreeTextStyle startStyle;

  /// 行宽度
  int width = 0;

  /// 行高度
  int height = 0;

  /// 下降距离（基线以下）
  int descent = 0;

  /// 左缩进
  int leftIndent = 0;

  /// 内部空格数
  int spaceCount = 0;

  /// 段前间距
  int vSpaceBefore = 0;

  /// 段后间距
  int vSpaceAfter = 0;

  /// 是否可见（包含可渲染元素）
  bool isVisible = false;

  /// 是否使用了 previousInfo
  bool previousInfoUsed = false;

  /// Y 位置（在 prepareTextArea 中设置，用于背景绘制）
  int y = 0;

  TextLine(
    this.paragraphCursor,
    this.startElementIndex,
    this.startCharIndex,
    this.startStyle,
  )   : elementCount = paragraphCursor.getElementCount(),
        realStartElementIndex = startElementIndex,
        realStartCharIndex = startCharIndex,
        endElementIndex = startElementIndex,
        endCharIndex = startCharIndex;

  /// 是否是段落的最后一行
  bool isEndOfParagraph() {
    return endElementIndex >= elementCount;
  }

  /// 调整行高（与前一行的间距处理）
  void adjust(TextLine? previous) {
    if (!previousInfoUsed && previous != null) {
      height -= min(previous.vSpaceAfter, vSpaceBefore);
      previousInfoUsed = true;
    }
  }

  @override
  String toString() =>
      'TextLine(start=$startElementIndex:$startCharIndex, end=$endElementIndex:$endCharIndex, w=$width, h=$height)';
}
