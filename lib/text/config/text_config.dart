import '../style/tree_text_style.dart';
import '../tag/text_tag_type.dart';

/// 文本配置项
class TextConfig {
  /// 页面边距
  int marginTop;
  int marginBottom;
  int marginLeft;
  int marginRight;

  /// 文字颜色
  int textColor;

  /// 背景颜色
  int bgColor;

  /// 搜索高亮背景色（ARGB）
  int searchHighlightColor;

  /// 壁纸路径
  String? wallpaperPath;

  /// 基础文本样式
  final TreeTextStyle _baseTextStyle;

  TextConfig({
    this.marginTop = 16,
    this.marginBottom = 16,
    this.marginLeft = 24,
    this.marginRight = 24,
    this.textColor = 0xFF333333,
    this.bgColor = 0xFFF5F0E8,
    this.searchHighlightColor = 0x55FF9800,
    this.wallpaperPath,
    TreeTextStyle? baseTextStyle,
  }) : _baseTextStyle = baseTextStyle ?? TreeTextStyle();

  int getMarginTop() => marginTop;
  int getMarginBottom() => marginBottom;
  int getMarginLeft() => marginLeft;
  int getMarginRight() => marginRight;
  int getTextColor() => textColor;
  int getBgColor() => bgColor;
  TreeTextStyle getBaseTextStyle() => _baseTextStyle;

  /// 获取控制标签装饰样式
  TreeTextStyle getControlDecoratedStyle(TreeTextStyle parent, int controlType) {
    switch (controlType) {
      case TextControlType.h1:
        return parent.createChild(fontSize: 28, bold: true, spaceBefore: 12, spaceAfter: 8);
      case TextControlType.h2:
        return parent.createChild(fontSize: 24, bold: true, spaceBefore: 10, spaceAfter: 6);
      case TextControlType.h3:
        return parent.createChild(fontSize: 21, bold: true, spaceBefore: 8, spaceAfter: 4);
      case TextControlType.h4:
        return parent.createChild(fontSize: 18, bold: true, spaceBefore: 6, spaceAfter: 4);
      case TextControlType.h5:
        return parent.createChild(fontSize: 16, bold: true, spaceBefore: 4, spaceAfter: 2);
      case TextControlType.h6:
        return parent.createChild(fontSize: 14, bold: true, spaceBefore: 4, spaceAfter: 2);
      case TextControlType.strong:
      case TextControlType.bold:
        return parent.createChild(bold: true);
      case TextControlType.emphasis:
      case TextControlType.italic:
        return parent.createChild(italic: true);
      case TextControlType.code:
      case TextControlType.tt:
        return parent.createChild(
          fontFamily: 'monospace',
          backgroundColor: 0xFFF0F0F0, // 行内代码浅灰背景
        );
      case TextControlType.superscript:
        return parent.createChild(fontSize: (parent.getFontSize() * 0.7).toInt(), verticalAlign: -4);
      case TextControlType.subscript:
        return parent.createChild(fontSize: (parent.getFontSize() * 0.7).toInt(), verticalAlign: 4);
      case TextControlType.strike:
        return parent.createChild(strikeThrough: true);

      // === Markdown 扩展样式（微信公众号风格） ===
      case TextControlType.blockquote:
        return parent.createChild(
          leftIndent: 16,
          spaceBefore: 8,
          spaceAfter: 8,
        );
      case TextControlType.highlight:
        return parent.createChild(backgroundColor: 0xFFFFF3B0); // 黄色高亮背景
      case TextControlType.link:
        return parent.createChild(); // 颜色在渲染层处理（#576b95）
      case TextControlType.codeBlockLine:
        return parent.createChild(fontFamily: 'monospace');
      case TextControlType.tableCell:
        return parent.createChild();
      case TextControlType.tableHeaderCell:
        return parent.createChild(bold: true);
      case TextControlType.horizontalRule:
        return parent.createChild();
      case TextControlType.imageCaption:
        return parent.createChild(
          fontSize: 12,
          alignment: 1, // center
          spaceBefore: 4,
          spaceAfter: 8,
        );
      case TextControlType.taskChecked:
      case TextControlType.taskUnchecked:
        return parent.createChild();
      case TextControlType.kbd:
        return parent.createChild(
          fontFamily: 'monospace',
          backgroundColor: 0xFFF0F0F0, // 浅灰背景
        );
      case TextControlType.footnoteRef:
        return parent.createChild(
          fontSize: (parent.getFontSize() * 0.7).toInt(),
          verticalAlign: -4,
        );
      case TextControlType.underline:
        return parent.createChild(underline: true);
      default:
        return parent.createChild();
    }
  }

  /// 获取 CSS 装饰样式
  TreeTextStyle getCSSDecoratedStyle(TreeTextStyle parent, dynamic styleTag) {
    // TODO: 根据 styleTag 中的 featureMask 和 lengths 创建样式
    return parent.createChild();
  }
}
