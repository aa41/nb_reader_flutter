import '../tag/text_tag.dart';
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

  @override
  String toString() =>
      'TextContent(tags=${tags.length}, resources=${resources.length})';
}
