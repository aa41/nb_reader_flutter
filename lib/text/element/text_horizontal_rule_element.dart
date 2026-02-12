import 'text_element.dart';

/// 分割线元素 — 占据整行，固定高度
class TextHorizontalRuleElement extends TextElement {
  /// 分割线上下间距
  static const int vPadding = 24;

  /// 分割线本身高度
  static const int lineHeight = 1;

  /// 总高度 = 上间距 + 线高 + 下间距
  static const int totalHeight = vPadding + lineHeight + vPadding;

  const TextHorizontalRuleElement();

  @override
  String toString() => 'TextHorizontalRuleElement';
}
