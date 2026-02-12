import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'text_element.dart';

/// 语法高亮区间
class HighlightSpan {
  final int start;
  final int end;
  final int color; // ARGB

  const HighlightSpan(this.start, this.end, this.color);
}

/// 代码块元素 — 整块参与分页和渲染
class TextCodeBlockElement extends TextElement {
  /// 编程语言标识符（如 dart, json, python）
  final String? language;

  /// 代码行列表
  final List<String> lines;

  /// 每行的语法高亮区间（可选）
  final List<List<HighlightSpan>>? highlightSpans;

  /// 代码块内边距
  static const int paddingH = 16;
  static const int paddingV = 14;

  /// 代码块外边距（上下）— 与相邻内容的间距
  static const int outerMarginV = 16;

  /// 代码块圆角
  static const double borderRadius = 6.0;

  /// 语言标签高度
  static const int langLabelHeight = 22;

  /// 代码行高（必须 >= 实际 TextPainter 渲染高度，防重叠）
  /// 13px 字体 * height:1.4 ≈ 18.2，取 20 留余量
  static const double codeLineHeight = 20.0;

  /// 代码字体大小
  static const double codeFontSize = 13.0;

  /// 代码文本样式（drawCodeBlock 与高度计算共用）
  static const TextStyle codeTextStyle = TextStyle(
    fontSize: codeFontSize,
    color: Color(0xFF333333),
    fontFamily: 'monospace',
    height: 1.4,
  );

  TextCodeBlockElement({
    this.language,
    required this.lines,
    this.highlightSpans,
  });

  /// 缓存：自动换行后的每行视觉行数
  List<int>? _wrappedLineCounts;
  double? _cachedAvailableWidth;

  /// 计算自动换行后的总视觉行数（带缓存）
  int computeWrappedLineCount(double availableWidth) {
    if (_cachedAvailableWidth == availableWidth && _wrappedLineCounts != null) {
      return _wrappedLineCounts!.fold(0, (a, b) => a + b);
    }
    _cachedAvailableWidth = availableWidth;
    _wrappedLineCounts = _measureWrappedLines(availableWidth);
    return _wrappedLineCounts!.fold(0, (a, b) => a + b);
  }

  /// 获取每行的视觉行数（用于绘制时计算 y 偏移）
  List<int> getWrappedLineCounts(double availableWidth) {
    if (_cachedAvailableWidth == availableWidth && _wrappedLineCounts != null) {
      return _wrappedLineCounts!;
    }
    _cachedAvailableWidth = availableWidth;
    _wrappedLineCounts = _measureWrappedLines(availableWidth);
    return _wrappedLineCounts!;
  }

  List<int> _measureWrappedLines(double availableWidth) {
    final result = <int>[];
    for (final line in lines) {
      if (line.isEmpty) {
        result.add(1);
        continue;
      }
      final painter = TextPainter(
        text: TextSpan(text: line, style: codeTextStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout(maxWidth: availableWidth);
      final count = painter.computeLineMetrics().length;
      result.add(count < 1 ? 1 : count);
      painter.dispose();
    }
    return result;
  }

  @override
  String toString() => 'TextCodeBlockElement(lang=$language, lines=${lines.length})';
}
