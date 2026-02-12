import 'package:xml/xml.dart';

import '../../parser/format_plugin.dart';
import '../../text/entity/text_content.dart';
import '../../text/tag/text_tag.dart';
import '../../text/tag/text_tag_type.dart';

/// XHTML 内容解析器
/// 将 EPUB 的 XHTML 章节文件解析为 TextTag 列表
/// 简化移植自 C++ XHTMLReader，处理常用 HTML 标签
class XhtmlContentReader {
  /// HTML 标签到 TextControlType 的映射
  static const _controlTagMap = <String, int>{
    'strong': TextControlType.strong,
    'b': TextControlType.bold,
    'em': TextControlType.emphasis,
    'i': TextControlType.italic,
    'code': TextControlType.code,
    'tt': TextControlType.tt,
    'kbd': TextControlType.code,
    'var': TextControlType.code,
    'samp': TextControlType.code,
    'cite': TextControlType.cite,
    'sub': TextControlType.subscript,
    'sup': TextControlType.superscript,
    'dfn': TextControlType.dfn,
    'strike': TextControlType.strike,
    's': TextControlType.strike,
    'del': TextControlType.strike,
  };

  /// 段落级标签（会创建新段落）
  static const _paragraphTags = {
    'p', 'div', 'dt', 'dd', 'td', 'th', 'blockquote', 'section', 'article',
  };

  /// 标题标签
  static const _headingTagMap = <String, int>{
    'h1': TextControlType.h1,
    'h2': TextControlType.h2,
    'h3': TextControlType.h3,
    'h4': TextControlType.h4,
    'h5': TextControlType.h5,
    'h6': TextControlType.h6,
  };

  /// 解析 XHTML 内容为 TextTag 列表
  ///
  /// [startFragmentId] — 如果非空，只从包含此 ID 的元素开始提取内容
  /// [endFragmentId]   — 如果非空，到包含此 ID 的元素之前停止提取
  /// 用于支持单个 XHTML 文件包含多个章节的 EPUB 格式
  static TextContent parse(
    String xhtmlContent, {
    ImageDataResolver? imageDataResolver,
    String? startFragmentId,
    String? endFragmentId,
  }) {
    final tags = <TextTag>[];

    try {
      final doc = XmlDocument.parse(xhtmlContent);
      // 查找 body 元素
      final bodies = doc.findAllElements('body');
      if (bodies.isNotEmpty) {
        if (startFragmentId != null || endFragmentId != null) {
          // 片段模式：只提取 startFragment 到 endFragment 之间的内容
          final state = _FragmentState(
            startId: startFragmentId,
            endId: endFragmentId,
            // 如果没有 startFragment，从头开始
            started: startFragmentId == null,
          );
          _processElementWithFragment(bodies.first, tags, imageDataResolver, state);
        } else {
          _processElement(bodies.first, tags, imageDataResolver);
        }
      }
    } catch (_) {
      // XHTML 解析失败，尝试提取纯文本
      final text = _extractPlainText(xhtmlContent);
      if (text.isNotEmpty) {
        tags.add(const TextParagraphTag(TextParagraphType.textParagraph));
        tags.add(TextControlTag(TextControlType.regular, true));
        tags.add(TextContentTag(text));
      }
    }

    // 添加结束标记
    tags.add(const TextParagraphTag(TextParagraphType.endOfSectionParagraph));

    return TextContent(tags: tags);
  }

  /// 递归处理 XML 元素
  static void _processElement(XmlElement element, List<TextTag> tags,
      [ImageDataResolver? imageDataResolver]) {
    final tagName = element.localName.toLowerCase();

    // 处理标题标签
    if (_headingTagMap.containsKey(tagName)) {
      _handleHeading(element, tags, _headingTagMap[tagName]!, imageDataResolver);
      return;
    }

    // 处理段落级标签
    if (_paragraphTags.contains(tagName)) {
      _handleParagraph(element, tags, imageDataResolver);
      return;
    }

    // 处理内联控制标签
    if (_controlTagMap.containsKey(tagName)) {
      _handleControl(element, tags, _controlTagMap[tagName]!, imageDataResolver);
      return;
    }

    // 处理特殊标签
    switch (tagName) {
      case 'br':
        // 换行 → 新段落
        tags.add(const TextParagraphTag(TextParagraphType.textParagraph));
        tags.add(TextControlTag(TextControlType.regular, true));
        return;
      case 'img':
        _handleImage(element, tags, imageDataResolver);
        return;
      case 'image': // SVG image element
        _handleSvgImage(element, tags, imageDataResolver);
        return;
      case 'a':
        _handleAnchor(element, tags, imageDataResolver);
        return;
      case 'pre':
        _handlePreformatted(element, tags);
        return;
      case 'ul':
      case 'ol':
        _handleList(element, tags, tagName == 'ol', imageDataResolver);
        return;
      case 'li':
        _handleListItem(element, tags, imageDataResolver);
        return;
      case 'svg':
        // SVG 元素中可能包含 image 子元素
        _processChildren(element, tags, imageDataResolver);
        return;
      default:
        // 其他标签：递归处理子节点
        _processChildren(element, tags, imageDataResolver);
    }
  }

  /// 处理标题元素
  static void _handleHeading(XmlElement element, List<TextTag> tags,
      int controlType, [ImageDataResolver? imageDataResolver]) {
    tags.add(const TextParagraphTag(TextParagraphType.textParagraph));
    tags.add(TextControlTag(controlType, true));

    _processChildren(element, tags, imageDataResolver);

    tags.add(TextControlTag(controlType, false));
  }

  /// 处理段落元素
  static void _handleParagraph(XmlElement element, List<TextTag> tags,
      [ImageDataResolver? imageDataResolver]) {
    tags.add(const TextParagraphTag(TextParagraphType.textParagraph));
    tags.add(TextControlTag(TextControlType.regular, true));

    _processChildren(element, tags, imageDataResolver);
  }

  /// 处理内联控制标签
  static void _handleControl(XmlElement element, List<TextTag> tags,
      int controlType, [ImageDataResolver? imageDataResolver]) {
    tags.add(TextControlTag(controlType, true));
    _processChildren(element, tags, imageDataResolver);
    tags.add(TextControlTag(controlType, false));
  }

  /// 处理图片
  static void _handleImage(XmlElement element, List<TextTag> tags,
      [ImageDataResolver? imageDataResolver]) {
    final src = element.getAttribute('src') ?? '';
    if (src.isEmpty) return;

    // 尝试加载图片数据
    final imageData = imageDataResolver?.call(src);

    // 图片单独成段，保证布局正确
    tags.add(const TextParagraphTag(TextParagraphType.textParagraph));
    tags.add(TextControlTag(TextControlType.regular, true));
    tags.add(TextImageTag(src, imageData: imageData));
  }

  /// 处理 SVG image 元素 (image xlink:href)
  static void _handleSvgImage(XmlElement element, List<TextTag> tags,
      [ImageDataResolver? imageDataResolver]) {
    // SVG image 使用 xlink:href 或 href 属性
    final href = element.getAttribute('href') ??
        element.getAttribute('xlink:href') ??
        '';
    if (href.isEmpty) return;

    final imageData = imageDataResolver?.call(href);
    tags.add(const TextParagraphTag(TextParagraphType.textParagraph));
    tags.add(TextControlTag(TextControlType.regular, true));
    tags.add(TextImageTag(href, imageData: imageData));
  }

  /// 处理锚点/链接
  static void _handleAnchor(XmlElement element, List<TextTag> tags,
      [ImageDataResolver? imageDataResolver]) {
    // 简化处理：忽略链接属性，只输出文本内容
    _processChildren(element, tags, imageDataResolver);
  }

  /// 处理预格式化文本
  static void _handlePreformatted(XmlElement element, List<TextTag> tags) {
    tags.add(const TextParagraphTag(TextParagraphType.textParagraph));
    tags.add(TextControlTag(TextControlType.preformatted, true));

    final text = element.innerText;
    // 按行拆分
    final lines = text.split('\n');
    for (int i = 0; i < lines.length; i++) {
      if (i > 0) {
        tags.add(const TextParagraphTag(TextParagraphType.textParagraph));
        tags.add(TextControlTag(TextControlType.preformatted, true));
      }
      if (lines[i].isNotEmpty) {
        tags.add(TextContentTag(lines[i]));
      }
    }

    tags.add(TextControlTag(TextControlType.preformatted, false));
  }

  /// 处理列表
  static void _handleList(XmlElement element, List<TextTag> tags,
      bool ordered, [ImageDataResolver? imageDataResolver]) {
    _processChildren(element, tags, imageDataResolver);
  }

  /// 处理列表项
  static void _handleListItem(XmlElement element, List<TextTag> tags,
      [ImageDataResolver? imageDataResolver]) {
    tags.add(const TextParagraphTag(TextParagraphType.textParagraph));
    tags.add(TextControlTag(TextControlType.regular, true));
    // 添加缩进
    tags.add(const TextFixedHSpaceTag(3));
    tags.add(const TextContentTag('• '));

    _processChildren(element, tags, imageDataResolver);
  }

  /// 递归处理子节点
  static void _processChildren(XmlElement element, List<TextTag> tags,
      [ImageDataResolver? imageDataResolver]) {
    for (final child in element.children) {
      if (child is XmlText) {
        final text = child.value;
        // 合并空白字符
        final normalized = text.replaceAll(RegExp(r'\s+'), ' ');
        if (normalized.trim().isNotEmpty) {
          tags.add(TextContentTag(normalized));
        }
      } else if (child is XmlElement) {
        _processElement(child, tags, imageDataResolver);
      }
    }
  }

  // === 片段模式处理（单文件多章节 EPUB） ===

  /// 检查元素是否包含指定 ID
  static bool _elementHasId(XmlElement element, String id) {
    return element.getAttribute('id') == id;
  }

  /// 递归检查元素及其后代是否包含指定 ID
  static bool _subtreeContainsId(XmlElement element, String id) {
    if (element.getAttribute('id') == id) return true;
    for (final child in element.children.whereType<XmlElement>()) {
      if (_subtreeContainsId(child, id)) return true;
    }
    return false;
  }

  /// 片段模式下递归处理元素
  static void _processElementWithFragment(
    XmlElement element,
    List<TextTag> tags,
    ImageDataResolver? imageDataResolver,
    _FragmentState state,
  ) {
    if (state.ended) return;

    // 检查当前元素是否是开始锡点
    if (!state.started && state.startId != null) {
      if (_elementHasId(element, state.startId!)) {
        state.started = true;
      }
    }

    // 检查当前元素是否是结束锡点
    if (state.started && state.endId != null) {
      if (_elementHasId(element, state.endId!)) {
        state.ended = true;
        return;
      }
    }

    if (state.started) {
      // 已进入目标范围
      if (state.endId != null && _subtreeContainsId(element, state.endId!)) {
        // 子树中包含结束锡点，需要逐子节点处理
        _processChildrenWithFragment(element, tags, imageDataResolver, state);
      } else {
        // 子树中不包含结束锡点，整个元素正常处理
        _processElement(element, tags, imageDataResolver);
      }
    } else {
      // 还未开始，检查子树中是否包含 startId
      if (state.startId != null && _subtreeContainsId(element, state.startId!)) {
        _processChildrenWithFragment(element, tags, imageDataResolver, state);
      }
    }
  }

  /// 片段模式下递归处理子节点
  static void _processChildrenWithFragment(
    XmlElement element,
    List<TextTag> tags,
    ImageDataResolver? imageDataResolver,
    _FragmentState state,
  ) {
    for (final child in element.children) {
      if (state.ended) break;
      if (child is XmlText) {
        if (state.started) {
          final text = child.value;
          final normalized = text.replaceAll(RegExp(r'\s+'), ' ');
          if (normalized.trim().isNotEmpty) {
            tags.add(TextContentTag(normalized));
          }
        }
      } else if (child is XmlElement) {
        _processElementWithFragment(child, tags, imageDataResolver, state);
      }
    }
  }

  /// 从 HTML 内容中提取纯文本（降级处理）
  static String _extractPlainText(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

/// 片段提取状态
class _FragmentState {
  final String? startId;
  final String? endId;
  bool started;
  bool ended = false;

  _FragmentState({
    this.startId,
    this.endId,
    this.started = false,
  });
}
