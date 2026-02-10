import 'text_element.dart';
import '../tag/text_tag.dart';

/// 样式元素 - 包含 CSS 或 Other 样式标签
class TextStyleElement extends TextElement {
  final TextTag styleTag; // TextCssStyleTag 或 TextOtherStyleTag

  const TextStyleElement(this.styleTag);

  @override
  String toString() => 'TextStyleElement($styleTag)';
}
