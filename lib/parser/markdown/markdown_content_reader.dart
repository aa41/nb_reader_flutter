import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:markdown/markdown.dart' as md;

import '../../text/entity/text_content.dart';
import '../../text/tag/text_tag.dart';
import '../../text/tag/text_tag_type.dart';

/// 图片来源类型
enum _ImageSourceType {
  network,     // http:// or https://
  base64,      // data:image/...;base64,...
  localAbs,    // /absolute/path
  relative,    // ./relative or relative
}

/// Markdown 内容解析器
/// 将 Markdown 文本解析为 TextTag 列表（通过 markdown 包的 AST）
class MarkdownContentReader {
  /// 解析 Markdown 文本
  ///
  /// [markdownText] — 原始 Markdown 文本
  /// [basePath] — .md 文件所在目录（用于解析相对路径图片）
  /// 移除 HTML 注释（块级和行内）
  static final _htmlCommentPattern = RegExp(r'<!--[\s\S]*?-->', multiLine: true);

  static TextContent parse(
    String markdownText, {
    String? basePath,
  }) {
    // 预处理：移除 HTML 注释（块级注释不会经过 visitText）
    final cleaned = markdownText.replaceAll(_htmlCommentPattern, '');

    // 使用 GFM 扩展集（支持表格、删除线、任务列表等）
    final document = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      encodeHtml: false,
    );

    final nodes = document.parse(cleaned);
    final visitor = _TagBuildVisitor(basePath: basePath);

    for (final node in nodes) {
      node.accept(visitor);
    }

    // 添加结束标记
    visitor.tags.add(
      const TextParagraphTag(TextParagraphType.endOfSectionParagraph),
    );

    return TextContent(tags: visitor.tags);
  }
}

/// AST 访问者 — 将 markdown AST 转换为 TextTag 列表
class _TagBuildVisitor implements md.NodeVisitor {
  final List<TextTag> tags = [];
  final String? basePath;

  /// 当前引用块嵌套深度
  int _blockquoteDepth = 0;

  /// 列表嵌套栈：true=有序, false=无序
  final List<bool> _listStack = [];

  /// 有序列表当前序号栈
  final List<int> _orderedListCounters = [];

  /// 列表项打开的控制标签类型栈（用于 visitElementAfter 关闭）
  final List<int> _liControlTypeStack = [];


  _TagBuildVisitor({this.basePath});

  /// 匹配 HTML 行内标签和注释
  static final _inlineHtmlPattern = RegExp(
    r'<!--[\s\S]*?-->|'                    // HTML 注释
    r'<(mark|u|sub|sup|kbd|br)(?:\s[^>]*)?\/?>|' // 开标签/自闭合
    r'</(mark|u|sub|sup|kbd)>',              // 闭标签
    caseSensitive: false,
  );

  @override
  void visitText(md.Text text) {
    final content = text.text;
    if (content.isEmpty) return;

    // 如果不包含 HTML 标签，快速路径
    if (!content.contains('<')) {
      tags.add(TextContentTag(content));
      return;
    }

    int lastEnd = 0;
    for (final match in _inlineHtmlPattern.allMatches(content)) {
      // 标签前的纯文本
      if (match.start > lastEnd) {
        tags.add(TextContentTag(content.substring(lastEnd, match.start)));
      }

      final full = match.group(0)!;
      if (full.startsWith('<!--')) {
        // HTML 注释 → 跳过
      } else if (full.startsWith('</')) {
        // 闭标签
        final tagName = match.group(2)!.toLowerCase();
        _emitHtmlCloseTag(tagName);
      } else {
        // 开标签 / 自闭合标签
        final tagName = (match.group(1) ?? '').toLowerCase();
        if (tagName == 'br') {
          tags.add(const TextParagraphTag(TextParagraphType.textParagraph));
          tags.add(const TextControlTag(TextControlType.regular, true));
        } else {
          _emitHtmlOpenTag(tagName);
        }
      }
      lastEnd = match.end;
    }

    // 剩余文本
    if (lastEnd < content.length) {
      tags.add(TextContentTag(content.substring(lastEnd)));
    }
  }

  void _emitHtmlOpenTag(String tagName) {
    final controlType = _htmlTagToControlType(tagName);
    if (controlType != null) {
      tags.add(TextControlTag(controlType, true));
    }
  }

  void _emitHtmlCloseTag(String tagName) {
    final controlType = _htmlTagToControlType(tagName);
    if (controlType != null) {
      tags.add(TextControlTag(controlType, false));
    }
  }

  static int? _htmlTagToControlType(String tagName) {
    return switch (tagName) {
      'mark' => TextControlType.highlight,
      'u'    => TextControlType.underline,
      'sub'  => TextControlType.subscript,
      'sup'  => TextControlType.superscript,
      'kbd'  => TextControlType.kbd,
      _      => null,
    };
  }

  @override
  bool visitElementBefore(md.Element element) {
    switch (element.tag) {
      // === 块级元素 ===
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        tags.add(const TextParagraphTag(TextParagraphType.textParagraph));
        final level = int.parse(element.tag.substring(1));
        final controlType = _headingControlType(level);
        tags.add(TextControlTag(controlType, true));
        return true;

      case 'p':
        tags.add(const TextParagraphTag(TextParagraphType.textParagraph));
        // 引用块内的段落：先推入 blockquote 样式，再推 regular
        if (_blockquoteDepth > 0) {
          tags.add(const TextControlTag(TextControlType.blockquote, true));
        }
        tags.add(const TextControlTag(TextControlType.regular, true));
        return true;

      case 'blockquote':
        _blockquoteDepth++;
        // 不在此处添加 tag；块引用样式通过子段落的 ControlTag 处理
        return true;

      case 'pre':
        // 代码块：提取 <code> 子节点
        _handleCodeBlock(element);
        return false; // 不递归子节点

      case 'table':
        _handleTable(element);
        return false;

      case 'hr':
        tags.add(const TextParagraphTag(TextParagraphType.textParagraph));
        tags.add(const TextControlTag(TextControlType.regular, true));
        tags.add(const TextHorizontalRuleTag());
        tags.add(const TextControlTag(TextControlType.regular, false));
        return false;

      case 'ul':
        _listStack.add(false);
        return true;

      case 'ol':
        _listStack.add(true);
        final startAttr = element.attributes['start'];
        _orderedListCounters.add(
          startAttr != null ? int.tryParse(startAttr) ?? 1 : 1,
        );
        return true;

      case 'li':
        _handleListItem(element);
        return true;

      // === 行内元素 ===
      case 'strong':
        tags.add(const TextControlTag(TextControlType.strong, true));
        return true;

      case 'em':
        tags.add(const TextControlTag(TextControlType.emphasis, true));
        return true;

      case 'del':
        tags.add(const TextControlTag(TextControlType.strike, true));
        return true;

      case 'code':
        tags.add(const TextControlTag(TextControlType.code, true));
        return true;

      case 'a':
        final href = element.attributes['href'] ?? '';
        final title = element.attributes['title'];
        tags.add(TextLinkStartTag(href, title: title));
        tags.add(const TextControlTag(TextControlType.link, true));
        return true;

      case 'img':
        _handleImage(element);
        return false;

      case 'br':
        tags.add(const TextParagraphTag(TextParagraphType.textParagraph));
        tags.add(const TextControlTag(TextControlType.regular, true));
        return false;

      case 'sub':
        tags.add(const TextControlTag(TextControlType.subscript, true));
        return true;

      case 'sup':
        tags.add(const TextControlTag(TextControlType.superscript, true));
        return true;

      case 'mark':
        tags.add(const TextControlTag(TextControlType.highlight, true));
        return true;

      case 'kbd':
        tags.add(const TextControlTag(TextControlType.kbd, true));
        return true;

      case 'u':
        tags.add(const TextControlTag(TextControlType.underline, true));
        return true;

      case 'input':
        // 任务列表复选框：状态通过前缀符号表示
        final checked = element.attributes.containsKey('checked');
        final symbol = checked ? '☑ ' : '☐ ';
        tags.add(TextContentTag(symbol));
        return false;

      // section（脚注区域）
      case 'section':
        if (element.attributes['class'] == 'footnotes') {
          tags.add(const TextParagraphTag(TextParagraphType.textParagraph));
          tags.add(const TextControlTag(TextControlType.regular, true));
          tags.add(const TextHorizontalRuleTag());
          return true;
        }
        return true;

      default:
        return true;
    }
  }

  @override
  void visitElementAfter(md.Element element) {
    switch (element.tag) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        final level = int.parse(element.tag.substring(1));
        final controlType = _headingControlType(level);
        tags.add(TextControlTag(controlType, false));
        break;

      case 'p':
        tags.add(const TextControlTag(TextControlType.regular, false));
        if (_blockquoteDepth > 0) {
          tags.add(const TextControlTag(TextControlType.blockquote, false));
        }
        break;

      case 'blockquote':
        _blockquoteDepth--;
        break;

      case 'ul':
        _listStack.removeLast();
        break;

      case 'ol':
        _listStack.removeLast();
        _orderedListCounters.removeLast();
        break;

      case 'li':
        // 关闭 _handleListItem 打开的控制标签
        if (_liControlTypeStack.isNotEmpty) {
          final controlType = _liControlTypeStack.removeLast();
          tags.add(TextControlTag(controlType, false));
        }
        if (_blockquoteDepth > 0) {
          tags.add(const TextControlTag(TextControlType.blockquote, false));
        }
        break;

      case 'strong':
        tags.add(const TextControlTag(TextControlType.strong, false));
        break;

      case 'em':
        tags.add(const TextControlTag(TextControlType.emphasis, false));
        break;

      case 'del':
        tags.add(const TextControlTag(TextControlType.strike, false));
        break;

      case 'code':
        tags.add(const TextControlTag(TextControlType.code, false));
        break;

      case 'a':
        tags.add(const TextControlTag(TextControlType.link, false));
        tags.add(const TextLinkEndTag());
        break;

      case 'sub':
        tags.add(const TextControlTag(TextControlType.subscript, false));
        break;

      case 'sup':
        tags.add(const TextControlTag(TextControlType.superscript, false));
        break;

      case 'mark':
        tags.add(const TextControlTag(TextControlType.highlight, false));
        break;

      case 'kbd':
        tags.add(const TextControlTag(TextControlType.kbd, false));
        break;

      case 'u':
        tags.add(const TextControlTag(TextControlType.underline, false));
        break;
    }
  }

  // === 辅助方法 ===

  int _headingControlType(int level) {
    switch (level) {
      case 1: return TextControlType.h1;
      case 2: return TextControlType.h2;
      case 3: return TextControlType.h3;
      case 4: return TextControlType.h4;
      case 5: return TextControlType.h5;
      case 6: return TextControlType.h6;
      default: return TextControlType.h6;
    }
  }

  /// 处理代码块（<pre><code>）
  void _handleCodeBlock(md.Element preElement) {
    String? language;
    String code = '';

    for (final child in preElement.children ?? <md.Node>[]) {
      if (child is md.Element && child.tag == 'code') {
        // 从 class="language-xxx" 提取语言
        final className = child.attributes['class'] ?? '';
        if (className.startsWith('language-')) {
          language = className.substring('language-'.length);
        }
        code = child.textContent;
      }
    }

    // 按行拆分
    final lines = code.split('\n');
    // 移除尾部空行
    while (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }

    tags.add(const TextParagraphTag(TextParagraphType.textParagraph));
    tags.add(const TextControlTag(TextControlType.regular, true));
    tags.add(TextCodeBlockTag(language: language, lines: lines));
    tags.add(const TextControlTag(TextControlType.regular, false));
  }

  /// 处理表格
  void _handleTable(md.Element tableElement) {
    final headers = <String>[];
    final rows = <List<String>>[];
    final alignments = <int>[];

    for (final child in tableElement.children ?? <md.Node>[]) {
      if (child is md.Element) {
        if (child.tag == 'thead') {
          _parseTableHead(child, headers, alignments);
        } else if (child.tag == 'tbody') {
          _parseTableBody(child, rows);
        }
      }
    }

    // 确保 alignments 数量与 headers 一致
    while (alignments.length < headers.length) {
      alignments.add(0); // 默认左对齐
    }

    tags.add(const TextParagraphTag(TextParagraphType.textParagraph));
    tags.add(const TextControlTag(TextControlType.regular, true));
    tags.add(TextTableTag(
      headers: headers,
      rows: rows,
      alignments: alignments,
    ));
    tags.add(const TextControlTag(TextControlType.regular, false));
  }

  void _parseTableHead(md.Element thead, List<String> headers, List<int> alignments) {
    for (final tr in thead.children ?? <md.Node>[]) {
      if (tr is md.Element && tr.tag == 'tr') {
        for (final th in tr.children ?? <md.Node>[]) {
          if (th is md.Element && th.tag == 'th') {
            headers.add(th.textContent);
            // 解析对齐方式
            final style = th.attributes['style'] ?? '';
            if (style.contains('text-align: center')) {
              alignments.add(1);
            } else if (style.contains('text-align: right')) {
              alignments.add(2);
            } else {
              alignments.add(0);
            }
          }
        }
      }
    }
  }

  void _parseTableBody(md.Element tbody, List<List<String>> rows) {
    for (final tr in tbody.children ?? <md.Node>[]) {
      if (tr is md.Element && tr.tag == 'tr') {
        final row = <String>[];
        for (final td in tr.children ?? <md.Node>[]) {
          if (td is md.Element && td.tag == 'td') {
            row.add(td.textContent);
          }
        }
        rows.add(row);
      }
    }
  }

  /// 处理列表项
  void _handleListItem(md.Element li) {
    tags.add(const TextParagraphTag(TextParagraphType.textParagraph));

    // 引用块内的列表项也需要 blockquote 样式（用于背景渲染）
    if (_blockquoteDepth > 0) {
      tags.add(const TextControlTag(TextControlType.blockquote, true));
    }

    final nestLevel = _listStack.length;
    final isOrdered = _listStack.isNotEmpty && _listStack.last;

    // 检查是否是任务列表项
    final hasCheckbox = li.children?.any((child) =>
        child is md.Element &&
        child.tag == 'input' &&
        child.attributes['type'] == 'checkbox') ?? false;

    int controlType;
    if (hasCheckbox) {
      final checked = li.children?.any((child) =>
          child is md.Element &&
          child.tag == 'input' &&
          child.attributes.containsKey('checked')) ?? false;

      controlType = checked
          ? TextControlType.taskChecked
          : TextControlType.taskUnchecked;
      tags.add(TextControlTag(controlType, true));

      // 添加缩进
      if (nestLevel > 1) {
        tags.add(TextFixedHSpaceTag((nestLevel - 1) * 4));
      }
    } else if (isOrdered) {
      controlType = TextControlType.regular;
      tags.add(TextControlTag(controlType, true));

      // 添加缩进
      if (nestLevel > 1) {
        tags.add(TextFixedHSpaceTag((nestLevel - 1) * 4));
      }

      // 添加序号
      final counter = _orderedListCounters.isNotEmpty
          ? _orderedListCounters.last
          : 1;
      tags.add(TextContentTag('$counter. '));
      if (_orderedListCounters.isNotEmpty) {
        _orderedListCounters.last = counter + 1;
      }
    } else {
      controlType = TextControlType.regular;
      tags.add(TextControlTag(controlType, true));

      // 添加缩进
      if (nestLevel > 1) {
        tags.add(TextFixedHSpaceTag((nestLevel - 1) * 4));
      }

      // 添加圆点标记（按层级不同符号）
      final bullet = switch (nestLevel) {
        1 => '• ',
        2 => '◦ ',
        _ => '▪ ',
      };
      tags.add(TextContentTag(bullet));
    }

    // 记录打开的控制类型，用于 visitElementAfter 关闭
    _liControlTypeStack.add(controlType);
  }

  /// 处理图片
  void _handleImage(md.Element element) {
    final src = element.attributes['src'] ?? '';
    final alt = element.attributes['alt'] ?? '';
    final title = element.attributes['title'];

    if (src.isEmpty) return;

    final sourceType = _classifyImageSource(src);
    Uint8List? imageData;

    switch (sourceType) {
      case _ImageSourceType.base64:
        imageData = _decodeBase64Image(src);
        break;

      case _ImageSourceType.localAbs:
        try {
          final file = File(src);
          if (file.existsSync()) {
            imageData = file.readAsBytesSync();
          }
        } catch (_) {}
        break;

      case _ImageSourceType.relative:
        if (basePath != null) {
          try {
            final fullPath = '$basePath/$src';
            final file = File(fullPath);
            if (file.existsSync()) {
              imageData = file.readAsBytesSync();
            }
          } catch (_) {}
        }
        break;

      case _ImageSourceType.network:
        // 网络图片在引擎层异步下载，此处只传递 URL
        break;
    }

    // 图片作为行内块级元素：不单独开新段落。
    // 图片宽度 = textAreaWidth，会自然触发行断裂，效果等同于块级。
    // 这样可保持父级 <p> 的段落结构完整（blockquote 上下文等），
    // 避免产生空段落和孤立的 CLOSE 标签。
    tags.add(TextImageTag(src, imageData: imageData));

    // 添加图片说明（caption）
    if (title != null && title.isNotEmpty) {
      tags.add(const TextParagraphTag(TextParagraphType.textParagraph));
      tags.add(const TextControlTag(TextControlType.imageCaption, true));
      tags.add(TextContentTag(title));
      tags.add(const TextControlTag(TextControlType.imageCaption, false));
    } else if (alt.isNotEmpty) {
      tags.add(const TextParagraphTag(TextParagraphType.textParagraph));
      tags.add(const TextControlTag(TextControlType.imageCaption, true));
      tags.add(TextContentTag(alt));
      tags.add(const TextControlTag(TextControlType.imageCaption, false));
    }
  }

  /// 判断图片来源类型
  _ImageSourceType _classifyImageSource(String src) {
    if (src.startsWith('data:image/')) {
      return _ImageSourceType.base64;
    } else if (src.startsWith('http://') || src.startsWith('https://')) {
      return _ImageSourceType.network;
    } else if (src.startsWith('/')) {
      return _ImageSourceType.localAbs;
    } else {
      return _ImageSourceType.relative;
    }
  }

  /// 解码 Base64 图片
  Uint8List? _decodeBase64Image(String dataUri) {
    try {
      // data:image/png;base64,AAAA...
      final commaIdx = dataUri.indexOf(',');
      if (commaIdx < 0) return null;
      final base64Str = dataUri.substring(commaIdx + 1);
      return base64Decode(base64Str);
    } catch (_) {
      return null;
    }
  }
}
