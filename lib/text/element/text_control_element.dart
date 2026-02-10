import 'text_element.dart';

/// 控制元素 - 标记文本的样式类型（如 h1, strong, em 等）
class TextControlElement extends TextElement {
  final int type; // TextControlType
  final bool isStart;

  const TextControlElement(this.type, this.isStart);

  @override
  String toString() => 'TextControlElement(type=$type, isStart=$isStart)';
}
