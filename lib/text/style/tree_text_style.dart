import '../entity/text_metrics.dart';
import 'text_alignment_type.dart';

/// 样式树节点 - 支持样式继承
class TreeTextStyle {
  final TreeTextStyle? parent;

  final int _fontSize;
  final int _leftIndent;
  final int _rightIndent;
  final int _firstLineIndent;
  final int _spaceBefore;
  final int _spaceAfter;
  final int _alignment;
  final int _lineSpacePercent;
  final int _verticalAlign;
  final bool _bold;
  final bool _italic;
  final bool _underline;
  final bool _strikeThrough;
  final bool _allowHyphenations;
  final String? _fontFamily;
  final double _letterSpacing;
  final int? _color;
  final int? _bgColor;

  TreeTextStyle({
    this.parent,
    int fontSize = 18,
    int leftIndent = 0,
    int rightIndent = 0,
    int firstLineIndent = 0,
    int spaceBefore = 0,
    int spaceAfter = 0,
    int alignment = TextAlignmentType.alignLeft,
    int lineSpacePercent = 150,
    int verticalAlign = 0,
    bool bold = false,
    bool italic = false,
    bool underline = false,
    bool strikeThrough = false,
    bool allowHyphenations = true,
    String? fontFamily,
    double letterSpacing = 0.5,
    int? color,
    int? bgColor,
  })  : _fontSize = fontSize,
        _leftIndent = leftIndent,
        _rightIndent = rightIndent,
        _firstLineIndent = firstLineIndent,
        _spaceBefore = spaceBefore,
        _spaceAfter = spaceAfter,
        _alignment = alignment,
        _lineSpacePercent = lineSpacePercent,
        _verticalAlign = verticalAlign,
        _bold = bold,
        _italic = italic,
        _underline = underline,
        _strikeThrough = strikeThrough,
        _allowHyphenations = allowHyphenations,
        _fontFamily = fontFamily,
        _letterSpacing = letterSpacing,
        _color = color,
        _bgColor = bgColor;

  int getFontSize([TextMetrics? metrics]) => _fontSize;
  int getLeftIndent(TextMetrics metrics) => _leftIndent;
  int getRightIndent(TextMetrics metrics) => _rightIndent;
  int getFirstLineIndent(TextMetrics metrics) => _firstLineIndent;
  int getSpaceBefore(TextMetrics metrics) => _spaceBefore;
  int getSpaceAfter(TextMetrics metrics) => _spaceAfter;
  int getAlignment() => _alignment;
  int getLineSpacePercent() => _lineSpacePercent;
  int getVerticalAlign(TextMetrics metrics) => _verticalAlign;
  bool isBold() => _bold;
  bool isItalic() => _italic;
  bool isUnderline() => _underline;
  bool isStrikeThrough() => _strikeThrough;
  bool allowHyphenations() => _allowHyphenations;
  String? getFontFamily() => _fontFamily;
  double getLetterSpacing() => _letterSpacing;
  int? getColor() => _color ?? parent?.getColor();
  int? getBgColor() => _bgColor ?? parent?.getBgColor();

  /// 创建子样式
  TreeTextStyle createChild({
    int? fontSize,
    int? leftIndent,
    int? rightIndent,
    int? firstLineIndent,
    int? spaceBefore,
    int? spaceAfter,
    int? alignment,
    int? lineSpacePercent,
    int? verticalAlign,
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strikeThrough,
    bool? allowHyphenations,
    String? fontFamily,
    double? letterSpacing,
    int? color,
    int? bgColor,
  }) {
    return TreeTextStyle(
      parent: this,
      fontSize: fontSize ?? _fontSize,
      leftIndent: leftIndent ?? _leftIndent,
      rightIndent: rightIndent ?? _rightIndent,
      firstLineIndent: firstLineIndent ?? _firstLineIndent,
      spaceBefore: spaceBefore ?? _spaceBefore,
      spaceAfter: spaceAfter ?? _spaceAfter,
      alignment: alignment ?? _alignment,
      lineSpacePercent: lineSpacePercent ?? _lineSpacePercent,
      verticalAlign: verticalAlign ?? _verticalAlign,
      bold: bold ?? _bold,
      italic: italic ?? _italic,
      underline: underline ?? _underline,
      strikeThrough: strikeThrough ?? _strikeThrough,
      allowHyphenations: allowHyphenations ?? _allowHyphenations,
      fontFamily: fontFamily ?? _fontFamily,
      letterSpacing: letterSpacing ?? _letterSpacing,
      color: color ?? _color,
      bgColor: bgColor ?? _bgColor,
    );
  }

  @override
  String toString() => 'TreeTextStyle(fontSize=$_fontSize, bold=$_bold, italic=$_italic, letterSpacing=$_letterSpacing)';
}
