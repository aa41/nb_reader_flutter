/// 文本位置（抽象）
abstract class TextPosition implements Comparable<TextPosition> {
  int get chapterIndex;
  int get paragraphIndex;
  int get elementIndex;
  int get charIndex;

  @override
  int compareTo(TextPosition other) {
    int diff = chapterIndex - other.chapterIndex;
    if (diff != 0) return diff;
    diff = paragraphIndex - other.paragraphIndex;
    if (diff != 0) return diff;
    diff = elementIndex - other.elementIndex;
    if (diff != 0) return diff;
    return charIndex - other.charIndex;
  }

  /// 忽略 charIndex 的比较
  int compareToIgnoreChar(TextPosition other) {
    int diff = chapterIndex - other.chapterIndex;
    if (diff != 0) return diff;
    diff = paragraphIndex - other.paragraphIndex;
    if (diff != 0) return diff;
    return elementIndex - other.elementIndex;
  }

  bool operator >(TextPosition other) => compareTo(other) > 0;
  bool operator <(TextPosition other) => compareTo(other) < 0;
  bool operator >=(TextPosition other) => compareTo(other) >= 0;
  bool operator <=(TextPosition other) => compareTo(other) <= 0;
}

/// 固定位置（不可变）
class TextFixedPosition extends TextPosition {
  @override
  final int chapterIndex;
  @override
  final int paragraphIndex;
  @override
  final int elementIndex;
  @override
  final int charIndex;

  TextFixedPosition({
    required this.chapterIndex,
    required this.paragraphIndex,
    required this.elementIndex,
    required this.charIndex,
  });

  /// 从 TextPosition 创建快照
  factory TextFixedPosition.fromPosition(TextPosition pos) {
    return TextFixedPosition(
      chapterIndex: pos.chapterIndex,
      paragraphIndex: pos.paragraphIndex,
      elementIndex: pos.elementIndex,
      charIndex: pos.charIndex,
    );
  }

  @override
  String toString() =>
      'TextFixedPosition(ch=$chapterIndex, para=$paragraphIndex, elem=$elementIndex, char=$charIndex)';
}
