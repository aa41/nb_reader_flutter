import 'text_element.dart';

/// 固定水平间距元素
class TextFixedHSpaceElement extends TextElement {
  final int length;

  const TextFixedHSpaceElement._(this.length);

  /// 缓存常用实例
  static final Map<int, TextFixedHSpaceElement> _cache = {};

  static TextFixedHSpaceElement getElement(int length) {
    return _cache.putIfAbsent(length, () => TextFixedHSpaceElement._(length));
  }

  @override
  String toString() => 'TextFixedHSpaceElement(length=$length)';
}
