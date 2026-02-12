import 'text_element.dart';

/// 复选框元素（任务列表）
class TextCheckboxElement extends TextElement {
  final bool checked;

  /// 复选框尺寸
  static const int size = 16;

  /// 右侧间距
  static const int rightPadding = 6;

  const TextCheckboxElement(this.checked);

  @override
  String toString() => 'TextCheckboxElement(checked=$checked)';
}
