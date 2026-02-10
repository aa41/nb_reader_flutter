import '../element/text_element.dart';
import '../style/tree_text_style.dart';

/// 文本元素绘制区域
class TextElementArea {
  final int chapterIndex;
  final int paragraphIndex;
  final int elementIndex;
  final int charIndex;
  final int length;
  final bool isLastElement;
  final bool addHyphenationSign;
  final bool isStyleChange;
  final TreeTextStyle style;
  final TextElement element;

  /// 绘制坐标
  final int startX;
  final int endX;
  final int startY; // 实际是 endX 方向（源码命名有误差，保持一致）
  final int endY;

  const TextElementArea({
    required this.chapterIndex,
    required this.paragraphIndex,
    required this.elementIndex,
    required this.charIndex,
    required this.length,
    required this.isLastElement,
    required this.addHyphenationSign,
    required this.isStyleChange,
    required this.style,
    required this.element,
    required this.startX,
    required this.startY,
    required this.endX,
    required this.endY,
  });
}

/// 元素区域列表容器
class TextElementAreaVector {
  final List<TextElementArea> _areas = [];

  void add(TextElementArea area) => _areas.add(area);
  void clear() => _areas.clear();
  int size() => _areas.length;
  List<TextElementArea> areas() => _areas;
}
