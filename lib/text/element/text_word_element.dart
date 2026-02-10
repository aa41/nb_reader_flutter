import 'text_element.dart';

/// 文字元素 - 表示一个可渲染的单词/文本片段
class TextWordElement extends TextElement {
  /// 原始字符数据
  final List<int> data;

  /// 在 data 中的偏移
  final int offset;

  /// 字符长度
  final int length;

  /// 缓存的宽度（由 PaintContext 计算后缓存）
  int? _cachedWidth;

  TextWordElement(this.data, this.offset, this.length);

  /// 从字符串创建
  factory TextWordElement.fromString(String str) {
    final codes = str.codeUnits;
    return TextWordElement(codes, 0, codes.length);
  }

  /// 获取宽度（带缓存）
  int getWidth(dynamic paintContext) {
    _cachedWidth ??= paintContext.getStringWidth(data, offset, length);
    return _cachedWidth!;
  }

  /// 使宽度缓存失效
  void invalidateWidth() {
    _cachedWidth = null;
  }

  /// 获取字符串表示
  String getString() {
    return String.fromCharCodes(data, offset, offset + length);
  }

  @override
  String toString() => 'TextWordElement("${getString()}")';
}
