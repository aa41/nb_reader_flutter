import 'dart:io';
import 'dart:typed_data';

import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;

import '../../text/entity/text_content.dart';
import '../../utils/html_unescape.dart';
import '../../text/style/text_alignment_type.dart';
import '../../text/tag/text_tag.dart';
import '../../text/tag/text_tag_type.dart';
import 'code_highlighter.dart';

/// Markdown 内容解析器
/// 将 Markdown AST 转换为 TextTag 列表
class MarkdownReader {
  /// 本地图片基础路径（.md 文件所在目录）
  final String? basePath;

  /// 预渲染的表格图片缓存：tableKey → PNG bytes
  final Map<String, Uint8List> tableImages;

  MarkdownReader({this.basePath, this.tableImages = const {}});

  /// 解析 Markdown 文本为 TextContent
  TextContent parse(String markdownText) {
    final tags = <TextTag>[];
    final doc = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
    );
    final nodes = doc.parse(markdownText);

    for (final node in nodes) {
      _processNode(node, tags);
    }

    // 添加结束标记
    tags.add(const TextParagraphTag(TextParagraphType.endOfSectionParagraph));
    return TextContent(tags: tags);
  }

  void _processNode(md.Node node, List<TextTag> tags) {
    if (node is md.Element) {
      _processElement(node, tags);
    } else if (node is md.Text) {
      tags.add(TextContentTag(node.textContent));
    }
  }

  void _processElement(md.Element element, List<TextTag> tags) {
    switch (element.tag) {
      // 标题
      case 'h1':
        _emitHeading(element, tags, TextControlType.h1);
        break;
      case 'h2':
        _emitHeading(element, tags, TextControlType.h2);
        break;
      case 'h3':
        _emitHeading(element, tags, TextControlType.h3);
        break;
      case 'h4':
        _emitHeading(element, tags, TextControlType.h4);
        break;
      case 'h5':
        _emitHeading(element, tags, TextControlType.h5);
        break;
      case 'h6':
        _emitHeading(element, tags, TextControlType.h6);
        break;

      // 段落
      case 'p':
        tags.add(const TextParagraphTag(TextParagraphType.textParagraph));
        tags.add(const TextControlTag(TextControlType.regular, true));
        _processChildren(element, tags);
        break;

      // 粗体
      case 'strong':
        tags.add(const TextControlTag(TextControlType.strong, true));
        _processChildren(element, tags);
        tags.add(const TextControlTag(TextControlType.strong, false));
        break;

      // 斜体
      case 'em':
        tags.add(const TextControlTag(TextControlType.emphasis, true));
        _processChildren(element, tags);
        tags.add(const TextControlTag(TextControlType.emphasis, false));
        break;

      // 删除线
      case 'del':
        tags.add(const TextControlTag(TextControlType.strike, true));
        _processChildren(element, tags);
        tags.add(const TextControlTag(TextControlType.strike, false));
        break;

      // 行内代码
      case 'code':
        // 如果父元素是 pre，说明是代码块（在 pre case 中处理）
        tags.add(const TextControlTag(TextControlType.code, true));
        _processChildren(element, tags);
        tags.add(const TextControlTag(TextControlType.code, false));
        break;

      // 代码块
      case 'pre':
        _emitCodeBlock(element, tags);
        break;

      // 引用块
      case 'blockquote':
        _emitBlockquote(element, tags);
        break;

      // 列表
      case 'ul':
        _emitList(element, tags, ordered: false);
        break;
      case 'ol':
        _emitList(element, tags, ordered: true);
        break;
      case 'li':
        _processChildren(element, tags);
        break;

      // 任务列表复选框
      case 'input':
        final checked = element.attributes['checked'] != null;
        tags.add(TextContentTag(checked ? '☑ ' : '☐ '));
        break;

      // 图片
      case 'img':
        _emitImage(element, tags);
        break;

      // 链接 → 展平为纯文本
      case 'a':
        _processChildren(element, tags);
        break;

      // 换行
      case 'br':
        tags.add(const TextParagraphTag(TextParagraphType.textParagraph));
        tags.add(const TextControlTag(TextControlType.regular, true));
        break;

      // 水平线（极简风格分割线，居中显示）
      case 'hr':
        tags.add(const TextParagraphTag(TextParagraphType.emptyLineParagraph));
        tags.add(const TextParagraphTag(TextParagraphType.textParagraph));
        tags.add(const TextControlTag(TextControlType.regular, true));
        tags.add(TextCssStyleTag(
          depth: 0,
          featureMask: 0,
          color: 0xFFBBBBBB,
          alignment: TextAlignmentType.alignCenter,
        ));
        tags.add(const TextContentTag('\u00b7\u2002\u2002\u00b7\u2002\u2002\u00b7'));
        tags.add(TextStyleCloseTag.instance);
        tags.add(const TextParagraphTag(TextParagraphType.emptyLineParagraph));
        break;

      // 表格
      case 'table':
        _emitTable(element, tags);
        break;

      // 其他元素：递归处理子节点
      default:
        _processChildren(element, tags);
    }
  }

  void _processChildren(md.Element element, List<TextTag> tags) {
    if (element.children == null) return;
    for (final child in element.children!) {
      _processNode(child, tags);
    }
  }

  /// 发射标题
  void _emitHeading(md.Element element, List<TextTag> tags, int controlType) {
    tags.add(const TextParagraphTag(TextParagraphType.textParagraph));
    tags.add(TextControlTag(controlType, true));
    _processChildren(element, tags);
    tags.add(TextControlTag(controlType, false));
  }

  /// 发射代码块（带语法高亮）
  void _emitCodeBlock(md.Element element, List<TextTag> tags) {
    // 代码块前加空行间距
    tags.add(const TextParagraphTag(TextParagraphType.emptyLineParagraph));
    // 提取语言和代码内容
    String? language;
    String code = '';

    final codeElement = _findCodeElement(element);
    if (codeElement != null) {
      // 从 class="language-xxx" 提取语言
      final className = codeElement.attributes['class'] ?? '';
      if (className.startsWith('language-')) {
        language = className.substring('language-'.length);
      }
      code = codeElement.textContent;
    } else {
    code = element.textContent;
    }

    // 解码 HTML 实体（markdown 库可能返回未解码的 &quot; 等）
    code = HtmlUnescape.unescape(code);

    // 移除尾部换行
    if (code.endsWith('\n')) code = code.substring(0, code.length - 1);

    // 语法高亮 tokenize
    final tokens = CodeHighlighter.highlight(code, language);

    // 按行发射，每行一个段落
    final lines = <List<HighlightToken>>[];
    var currentLine = <HighlightToken>[];
    for (final token in tokens) {
      // 按换行拆分 token
      final parts = token.text.split('\n');
      for (int i = 0; i < parts.length; i++) {
        if (i > 0) {
          lines.add(currentLine);
          currentLine = <HighlightToken>[];
        }
        if (parts[i].isNotEmpty) {
          currentLine.add(HighlightToken(parts[i], token.color));
        }
      }
    }
    if (currentLine.isNotEmpty) lines.add(currentLine);

    for (final line in lines) {
      tags.add(const TextParagraphTag(TextParagraphType.textParagraph));
      tags.add(const TextControlTag(TextControlType.preformatted, true));

      if (line.isEmpty) {
        tags.add(const TextContentTag(' ')); // 空行占位
      } else {
        for (final token in line) {
          if (token.color != null) {
            tags.add(TextCssStyleTag(depth: 0, featureMask: 0, color: token.color));
            tags.add(TextContentTag(token.text));
            tags.add(TextStyleCloseTag.instance);
          } else {
            tags.add(TextContentTag(token.text));
          }
        }
      }

      tags.add(const TextControlTag(TextControlType.preformatted, false));
    }
    // 代码块后加空行间距
    tags.add(const TextParagraphTag(TextParagraphType.emptyLineParagraph));
  }

  md.Element? _findCodeElement(md.Element element) {
    if (element.children == null) return null;
    for (final child in element.children!) {
      if (child is md.Element && child.tag == 'code') return child;
    }
    return null;
  }

  /// 发射引用块
  void _emitBlockquote(md.Element element, List<TextTag> tags) {
    if (element.children == null) return;
    for (final child in element.children!) {
      if (child is md.Element && child.tag == 'p') {
        tags.add(const TextParagraphTag(TextParagraphType.textParagraph));
        tags.add(const TextControlTag(TextControlType.cite, true));
        _processChildren(child, tags);
        tags.add(const TextControlTag(TextControlType.cite, false));
      } else if (child is md.Element && child.tag == 'blockquote') {
        // 嵌套引用
        _emitBlockquote(child, tags);
      } else {
        tags.add(const TextParagraphTag(TextParagraphType.textParagraph));
        tags.add(const TextControlTag(TextControlType.cite, true));
        _processNode(child, tags);
        tags.add(const TextControlTag(TextControlType.cite, false));
      }
    }
  }

  /// 发射列表
  void _emitList(md.Element element, List<TextTag> tags, {required bool ordered}) {
    if (element.children == null) return;
    int index = 1;
    for (final child in element.children!) {
      if (child is md.Element && child.tag == 'li') {
        tags.add(const TextParagraphTag(TextParagraphType.textParagraph));
        tags.add(const TextControlTag(TextControlType.regular, true));

        final prefix = ordered ? '${index++}. ' : '• ';
        tags.add(TextContentTag(prefix));

        // 处理 li 内容
        if (child.children != null) {
          for (final liChild in child.children!) {
            if (liChild is md.Element && liChild.tag == 'p') {
              _processChildren(liChild, tags);
            } else {
              _processNode(liChild, tags);
            }
          }
        }
      }
    }
  }

  /// 发射图片
  void _emitImage(md.Element element, List<TextTag> tags) {
    final src = element.attributes['src'] ?? '';
    if (src.isEmpty) return;

    Uint8List? imageData;

    // 本地图片：相对于 .md 文件路径解析
    if (!src.startsWith('http://') && !src.startsWith('https://')) {
      if (basePath != null) {
        // 使用 path 包规范化路径，正确处理 ./ 和 ../ 等相对路径
        final fullPath = p.isAbsolute(src)
            ? src
            : p.normalize(p.join(basePath!, src));
        final file = File(fullPath);
        if (file.existsSync()) {
          imageData = file.readAsBytesSync();
        }
      }
    }
    // 网络图片：imageData 为 null，由图片缓存系统异步处理

    tags.add(const TextParagraphTag(TextParagraphType.textParagraph));
    tags.add(const TextControlTag(TextControlType.regular, true));
    tags.add(TextImageTag(src, imageData: imageData));
  }

  /// 发射表格（使用预渲染的图片或回退为文本）
  void _emitTable(md.Element element, List<TextTag> tags) {
    // 提取表头和数据
    final headers = <String>[];
    final rows = <List<String>>[];

    if (element.children != null) {
      for (final section in element.children!) {
        if (section is md.Element) {
          if (section.tag == 'thead') {
            _extractTableRows(section, headers, null);
          } else if (section.tag == 'tbody') {
            _extractTableRows(section, null, rows);
          }
        }
      }
    }

    // 尝试使用预渲染的表格图片
    final tableKey = 'table_${headers.join('|')}_${rows.length}';
    final tableImageData = tableImages[tableKey];
    if (tableImageData != null) {
      tags.add(const TextParagraphTag(TextParagraphType.textParagraph));
      tags.add(const TextControlTag(TextControlType.regular, true));
      tags.add(TextImageTag(tableKey, imageData: tableImageData));
      return;
    }

    // 回退：以文本形式展示表格
    if (headers.isNotEmpty) {
      tags.add(const TextParagraphTag(TextParagraphType.textParagraph));
      tags.add(const TextControlTag(TextControlType.bold, true));
      tags.add(TextContentTag(headers.join(' │ ')));
      tags.add(const TextControlTag(TextControlType.bold, false));

      tags.add(const TextParagraphTag(TextParagraphType.textParagraph));
      tags.add(const TextControlTag(TextControlType.regular, true));
      tags.add(TextContentTag('─' * 30));
    }

    for (final row in rows) {
      tags.add(const TextParagraphTag(TextParagraphType.textParagraph));
      tags.add(const TextControlTag(TextControlType.regular, true));
      tags.add(TextContentTag(row.join(' │ ')));
    }
  }

  void _extractTableRows(md.Element section, List<String>? headers, List<List<String>>? rows) {
    if (section.children == null) return;
    for (final tr in section.children!) {
      if (tr is md.Element && tr.tag == 'tr' && tr.children != null) {
        final cells = <String>[];
        for (final cell in tr.children!) {
          if (cell is md.Element && (cell.tag == 'th' || cell.tag == 'td')) {
            cells.add(cell.textContent.trim());
          }
        }
        if (headers != null && headers.isEmpty) {
          headers.addAll(cells);
        } else if (rows != null) {
          rows.add(cells);
        }
      }
    }
  }
}
