import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// 表格图片渲染器
/// 使用 Canvas 直接绘制表格为 ui.Image → PNG bytes
class TableImageRenderer {
  static const double _cellPaddingH = 10;
  static const double _cellPaddingV = 8;
  static const double _borderWidth = 0.5;
  static const int _headerBgColor = 0xFFF5F5F5;
  static const int _borderColor = 0xFFCCCCCC;
  static const int _textColor = 0xFF333333;
  static const int _headerTextColor = 0xFF111111;
  static const double _fontSize = 13;

  /// 将表格数据渲染为 PNG 字节
  /// [headers] 表头行（可为空）
  /// [rows] 数据行
  /// [maxWidth] 最大宽度
  static Future<Uint8List?> render({
    List<String>? headers,
    required List<List<String>> rows,
    required double maxWidth,
  }) async {
    if (rows.isEmpty && (headers == null || headers.isEmpty)) return null;

    final allRows = <List<String>>[];
    if (headers != null && headers.isNotEmpty) allRows.add(headers);
    allRows.addAll(rows);

    final colCount = allRows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
    if (colCount == 0) return null;

    // 计算列宽（等分，减去边框）
    final availWidth = maxWidth - _borderWidth * (colCount + 1);
    final colWidth = availWidth / colCount;

    // 计算每行高度
    final rowHeights = <double>[];
    for (final row in allRows) {
      double maxH = 0;
      for (int c = 0; c < colCount; c++) {
        final text = c < row.length ? row[c] : '';
        final h = _measureTextHeight(text, colWidth - _cellPaddingH * 2);
        if (h > maxH) maxH = h;
      }
      rowHeights.add(maxH + _cellPaddingV * 2);
    }

    final totalHeight = rowHeights.fold<double>(0, (s, h) => s + h) +
        _borderWidth * (allRows.length + 1);
    final totalWidth = maxWidth;

    // 创建 Canvas 绘制
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, totalWidth, totalHeight));

    // 白色背景
    canvas.drawRect(
      Rect.fromLTWH(0, 0, totalWidth, totalHeight),
      Paint()..color = const Color(0xFFFFFFFF),
    );

    final borderPaint = Paint()
      ..color = const Color(_borderColor)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _borderWidth;

    double y = 0;
    for (int r = 0; r < allRows.length; r++) {
      final row = allRows[r];
      final rh = rowHeights[r];
      final isHeader = headers != null && headers.isNotEmpty && r == 0;

      // 表头背景
      if (isHeader) {
        canvas.drawRect(
          Rect.fromLTWH(0, y, totalWidth, rh + _borderWidth),
          Paint()..color = const Color(_headerBgColor),
        );
      }

      double x = 0;
      for (int c = 0; c < colCount; c++) {
        final text = c < row.length ? row[c] : '';
        final cellRect = Rect.fromLTWH(x, y, colWidth + _borderWidth, rh + _borderWidth);
        canvas.drawRect(cellRect, borderPaint);

        // 绘制文本
        _drawCellText(
          canvas,
          text,
          x + _cellPaddingH,
          y + _cellPaddingV,
          colWidth - _cellPaddingH * 2,
          isHeader: isHeader,
        );

        x += colWidth + _borderWidth;
      }

      y += rh + _borderWidth;
    }

    // 转为图片
    final picture = recorder.endRecording();
    final image = await picture.toImage(totalWidth.ceil(), totalHeight.ceil());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    image.dispose();

    return byteData?.buffer.asUint8List();
  }

  static double _measureTextHeight(String text, double maxWidth) {
    if (text.isEmpty) return _fontSize * 1.4;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: _fontSize, color: const Color(_textColor)),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout(maxWidth: maxWidth > 0 ? maxWidth : 50);
    final h = painter.height;
    painter.dispose();
    return h;
  }

  static void _drawCellText(
    Canvas canvas,
    String text,
    double x,
    double y,
    double maxWidth, {
    bool isHeader = false,
  }) {
    if (text.isEmpty) return;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: _fontSize,
          color: Color(isHeader ? _headerTextColor : _textColor),
          fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout(maxWidth: maxWidth > 0 ? maxWidth : 50);
    painter.paint(canvas, Offset(x, y));
    painter.dispose();
  }
}
