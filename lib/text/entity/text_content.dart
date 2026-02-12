import '../tag/text_tag.dart';
import '../tag/text_tag_type.dart';
import '../element/text_image_element.dart';

/// 章节内容数据（Dart 版本直接使用 Tag 列表，而非 ByteArray）
class TextContent {
  /// 资源信息（图片等）
  final Map<String, TextImage> resources;

  /// 内容标签列表
  final List<TextTag> tags;

  const TextContent({
    this.resources = const {},
    required this.tags,
  });

  /// 从 tag 结构构建纯文本（用于全文搜索）
  /// 偏移规则：TextContentTag 贡献 content.length 个字符，
  /// TextParagraphTag（非 endOfSection）之间以 '\n' 分隔。
  String toPlainText() {
    final buf = StringBuffer();
    for (final tag in tags) {
      if (tag is TextContentTag) {
        buf.write(tag.content);
      } else if (tag is TextParagraphTag &&
          tag.type != TextParagraphType.endOfSectionParagraph) {
        if (buf.isNotEmpty) buf.write('\n');
      }
    }
    return buf.toString();
  }

  @override
  String toString() =>
      'TextContent(tags=${tags.length}, resources=${resources.length})';
}
