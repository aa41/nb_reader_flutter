import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../element/text_image_element.dart';

/// 文本绘制上下文 - 封装 Flutter TextPainter 进行文字度量
/// 移植自 Kotlin TextPaintContext
class TextPaintContext {
  /// 当前字体参数
  double _fontSize = 18;
  bool _bold = false;
  bool _italic = false;
  bool _underline = false;
  bool _strikeThrough = false;
  String? _fontFamily;
  double _letterSpacing = 0;
  int _textColor = 0xFF333333;

  /// 缓存的度量值
  int? _cachedSpaceWidth;
  int? _cachedStringHeight;
  int? _cachedDescent;
  TextPainter? _cachedPainter;

  /// 设置字体参数
  void setFont({
    required double fontSize,
    required bool bold,
    required bool italic,
    required bool underline,
    required bool strikeThrough,
    String? fontFamily,
    double letterSpacing = 0,
  }) {
    if (_fontSize != fontSize ||
        _bold != bold ||
        _italic != italic ||
        _underline != underline ||
        _strikeThrough != strikeThrough ||
        _fontFamily != fontFamily ||
        _letterSpacing != letterSpacing) {
      _fontSize = fontSize;
      _bold = bold;
      _italic = italic;
      _underline = underline;
      _strikeThrough = strikeThrough;
      _fontFamily = fontFamily;
      _letterSpacing = letterSpacing;
      _invalidateCache();
    }
  }

  void _invalidateCache() {
    _cachedSpaceWidth = null;
    _cachedStringHeight = null;
    _cachedDescent = null;
    _cachedPainter = null;
  }

  /// 设置文本颜色
  void setTextColor(int color) {
    _textColor = color;
  }

  int getTextColor() => _textColor;

  /// 获取当前 TextStyle
  TextStyle getTextStyle() {
    return TextStyle(
      fontSize: _fontSize,
      fontWeight: _bold ? FontWeight.bold : FontWeight.normal,
      fontStyle: _italic ? FontStyle.italic : FontStyle.normal,
      decoration: _getDecoration(),
      fontFamily: _fontFamily,
      color: Color(_textColor),
      height: 1.0,
      letterSpacing: _letterSpacing != 0 ? _letterSpacing : null,
    );
  }

  TextDecoration _getDecoration() {
    final decorations = <TextDecoration>[];
    if (_underline) decorations.add(TextDecoration.underline);
    if (_strikeThrough) decorations.add(TextDecoration.lineThrough);
    return decorations.isEmpty
        ? TextDecoration.none
        : TextDecoration.combine(decorations);
  }

  /// 获取字符串宽度
  int getStringWidth(List<int> data, int offset, int length) {
    if (length <= 0) return 0;
    final str = String.fromCharCodes(data, offset, offset + length);
    return getStringWidthFromStr(str);
  }

  /// 从字符串获取宽度
  int getStringWidthFromStr(String str) {
    final painter = TextPainter(
      text: TextSpan(text: str, style: getTextStyle()),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final w = painter.width.ceil();
    painter.dispose();
    return w;
  }

  /// 获取字符串高度
  int getStringHeight() {
    if (_cachedStringHeight != null) return _cachedStringHeight!;
    final painter = _getMetricsPainter();
    _cachedStringHeight = painter.height.ceil();
    return _cachedStringHeight!;
  }

  /// 获取空格宽度
  int getSpaceWidth() {
    if (_cachedSpaceWidth != null) return _cachedSpaceWidth!;
    _cachedSpaceWidth = getStringWidthFromStr(' ');
    return _cachedSpaceWidth!;
  }

  /// 获取 descent（基线到文字底部的距离）
  int getDescent() {
    if (_cachedDescent != null) return _cachedDescent!;
    final painter = _getMetricsPainter();
    // 使用 computeLineMetrics 获取精确的 descent
    final metrics = painter.computeLineMetrics();
    if (metrics.isNotEmpty) {
      _cachedDescent = metrics.first.descent.ceil();
    } else {
      _cachedDescent = (_fontSize * 0.2).ceil();
    }
    return _cachedDescent!;
  }

  /// 固定图片布局高度（页面高度的 35%）
  /// 布局时占满一行宽度，绘制时按原始宽高比居中
  Size? getImageSize(TextImage image, Size textAreaSize) {
    final maxW = textAreaSize.width;
    final fixedH = textAreaSize.height * 0.35;
    // 布局尺寸：宽占满文本区域，高度固定
    return Size(maxW, fixedH.clamp(80.0, textAreaSize.height * 0.5));
  }

  TextPainter _getMetricsPainter() {
    _cachedPainter ??= TextPainter(
      text: TextSpan(text: 'Mg中', style: getTextStyle()),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return _cachedPainter!;
  }

  /// 当前字体大小
  double get fontSize => _fontSize;
  bool get isBold => _bold;
  bool get isItalic => _italic;
}
