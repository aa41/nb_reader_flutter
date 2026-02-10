import 'dart:typed_data';

/// 文本标签标记接口
abstract class TextTag {
  const TextTag();
}

/// 文本内容标签
class TextContentTag extends TextTag {
  final String content;
  const TextContentTag(this.content);

  @override
  String toString() => 'TextContentTag(content="${content.length > 30 ? '${content.substring(0, 30)}...' : content}")';
}

/// 控制标签（对应 HTML 控制标签如 h1-h6, strong, em 等）
class TextControlTag extends TextTag {
  final int type; // TextControlType
  final bool isStart;
  const TextControlTag(this.type, this.isStart);

  @override
  String toString() => 'TextControlTag(type=$type, isStart=$isStart)';
}

/// 段落标签
class TextParagraphTag extends TextTag {
  final int type; // TextParagraphType
  const TextParagraphTag(this.type);

  @override
  String toString() => 'TextParagraphTag(type=$type)';
}

/// CSS 样式标签
class TextCssStyleTag extends TextTag {
  final int depth;
  final int featureMask;
  final Map<int, int> lengths; // feature index -> value
  final Map<int, int> attributes; // feature index -> value

  const TextCssStyleTag({
    required this.depth,
    required this.featureMask,
    this.lengths = const {},
    this.attributes = const {},
  });

  @override
  String toString() => 'TextCssStyleTag(depth=$depth, featureMask=$featureMask)';
}

/// Other 样式标签
class TextOtherStyleTag extends TextTag {
  final int depth;
  final int featureMask;
  final Map<int, int> lengths;
  final Map<int, int> attributes;

  const TextOtherStyleTag({
    required this.depth,
    required this.featureMask,
    this.lengths = const {},
    this.attributes = const {},
  });

  @override
  String toString() => 'TextOtherStyleTag(depth=$depth, featureMask=$featureMask)';
}

/// 样式闭合标签
class TextStyleCloseTag extends TextTag {
  static const instance = TextStyleCloseTag._();
  const TextStyleCloseTag._();

  @override
  String toString() => 'TextStyleCloseTag';
}

/// 固定水平间距标签
class TextFixedHSpaceTag extends TextTag {
  final int length;
  const TextFixedHSpaceTag(this.length);

  @override
  String toString() => 'TextFixedHSpaceTag(length=$length)';
}

/// 图片标签
class TextImageTag extends TextTag {
  final String id;
  final bool isCover;
  final Uint8List? imageData; // 内嵌图片数据（EPUB）
  const TextImageTag(this.id, {this.isCover = false, this.imageData});

  @override
  String toString() => 'TextImageTag(id=$id, isCover=$isCover, hasData=${imageData != null})';
}

/// 身份标签
class TextIdentityTag extends TextTag {
  final String id;
  const TextIdentityTag(this.id);

  @override
  String toString() => 'TextIdentityTag(id=$id)';
}

/// 超链接控制标签（占位）
class TextHyperlinkControlTag extends TextTag {
  const TextHyperlinkControlTag();
}
