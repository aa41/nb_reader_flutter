import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

import '../element/text_checkbox_element.dart';
import '../element/text_code_block_element.dart';
import '../element/text_image_element.dart';
import '../element/text_table_element.dart';
import 'text_paint_context.dart';

/// 图片解码缓存（全局单例）
class _ImageDecodeCache {
  static final _ImageDecodeCache instance = _ImageDecodeCache._();
  _ImageDecodeCache._();

  final Map<String, ui.Image?> _cache = {};
  final Set<String> _loading = {};
  VoidCallback? onImageDecoded;

  /// 获取已解码的图片，如果未解码则异步解码并返回 null
  /// 支持本地图片（data != null）和网络图片（key 以 http:// 或 https:// 开头）
  ui.Image? get(String key, Uint8List? data) {
    if (_cache.containsKey(key)) return _cache[key];
    if (_loading.contains(key)) return null;

    if (data != null) {
      // 本地图片：直接解码
      _loading.add(key);
      _decodeAsync(key, data);
    } else if (_isNetworkUrl(key)) {
      // 网络图片：下载后解码
      _loading.add(key);
      _downloadAndDecodeAsync(key);
    }
    return null;
  }

  bool _isNetworkUrl(String key) =>
      key.startsWith('http://') || key.startsWith('https://');

  Future<void> _decodeAsync(String key, Uint8List data) async {
    try {
      final codec = await ui.instantiateImageCodec(data);
      final frame = await codec.getNextFrame();
      _cache[key] = frame.image;
      codec.dispose();
    } catch (_) {
      _cache[key] = null;
    }
    _loading.remove(key);
    onImageDecoded?.call();
  }

  /// 下载网络图片并解码
  Future<void> _downloadAndDecodeAsync(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        final bytes = response.bodyBytes;
        // 缓存原始字节以便其他地方使用
        _downloadedBytes[url] = bytes;
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        _cache[url] = frame.image;
        codec.dispose();
      } else {
        _cache[url] = null;
      }
    } catch (_) {
      _cache[url] = null;
    }
    _loading.remove(url);
    onImageDecoded?.call();
  }

  /// 获取已下载的网络图片原始字节
  Uint8List? getDownloadedBytes(String url) => _downloadedBytes[url];

  /// 已下载的网络图片原始字节缓存
  final Map<String, Uint8List> _downloadedBytes = {};
}

/// 文本绘制画布 - 封装 Flutter Canvas
/// 移植自 Kotlin TextCanvas
class TextCanvas {
  final TextPaintContext paintContext;
  final Canvas canvas;

  TextCanvas(this.paintContext, this.canvas);

  /// 设置图片解码回调（当图片解码完成时触发重绘）
  static set onImageDecoded(VoidCallback? cb) {
    _ImageDecodeCache.instance.onImageDecoded = cb;
  }

  /// 绘制字符串
  void drawString(int x, int y, List<int> data, int offset, int length) {
    if (length <= 0) return;
    final str = String.fromCharCodes(data, offset, offset + length);
    drawStringText(x, y, str);
  }

  /// 绘制字符串（文本版本）
  void drawStringText(int x, int y, String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: paintContext.getTextStyle()),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
    )..layout();
    painter.paint(canvas, Offset(x.toDouble(), y.toDouble() - painter.height));
    painter.dispose();
  }

  /// 绘制图片（在固定高度区域内居中显示，保持比例）
  void drawImage(int x, int y, TextImage image, Size textAreaSize) {
    // 获取固定区域尺寸（高度恒定，避免解码前后拖动）
    final areaSize = paintContext.getImageSize(image, textAreaSize);
    if (areaSize == null) return;

    // 固定区域的左上角
    final areaLeft = x.toDouble();
    final areaTop = y.toDouble() - areaSize.height;

    // 尝试从缓存获取解码后的图片
    final decoded = _ImageDecodeCache.instance.get(image.id, image.data);
    if (decoded != null) {
      image.decodedImage ??= decoded;

      // 计算在固定区域内的居中绘制位置和缩放尺寸
      final drawInfo = paintContext.getImageDrawInfo(image, areaSize);
      if (drawInfo != null) {
        final (drawSize, drawOffset) = drawInfo;
        final dst = Rect.fromLTWH(
          areaLeft + drawOffset.dx,
          areaTop + drawOffset.dy,
          drawSize.width,
          drawSize.height,
        );
        final src = Rect.fromLTWH(
          0, 0,
          decoded.width.toDouble(),
          decoded.height.toDouble(),
        );
        canvas.drawImageRect(decoded, src, dst, Paint());
      }
    } else {
      // 图片正在解码或无数据，在固定区域中央绘制占位框
      final placeholderW = areaSize.width * 0.5;
      final placeholderH = areaSize.height * 0.5;
      final placeholderLeft = areaLeft + (areaSize.width - placeholderW) / 2;
      final placeholderTop = areaTop + (areaSize.height - placeholderH) / 2;
      final rect = Rect.fromLTWH(
        placeholderLeft, placeholderTop, placeholderW, placeholderH,
      );

      final fillPaint = Paint()
        ..color = const Color(0xFFEEEEEE)
        ..style = PaintingStyle.fill;
      canvas.drawRect(rect, fillPaint);

      final borderPaint = Paint()
        ..color = const Color(0xFFCCCCCC)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawRect(rect, borderPaint);
    }
  }

  // ========== Markdown 块级绘制方法 ==========

  /// 绘制块级背景（引用块、代码块等）
  void drawBlockBackground({
    required Rect rect,
    required Color bgColor,
    Color? borderLeftColor,
    double borderLeftWidth = 3,
    double borderRadius = 0,
  }) {
    final bgPaint = Paint()
      ..color = bgColor
      ..style = PaintingStyle.fill;

    if (borderRadius > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(borderRadius)),
        bgPaint,
      );
    } else {
      canvas.drawRect(rect, bgPaint);
    }

    if (borderLeftColor != null) {
      final borderPaint = Paint()
        ..color = borderLeftColor
        ..style = PaintingStyle.fill;
      canvas.drawRect(
        Rect.fromLTWH(rect.left, rect.top, borderLeftWidth, rect.height),
        borderPaint,
      );
    }
  }

  /// 绘制分割线
  void drawHorizontalRule(int x, int y, int width, {Color color = const Color(0xFFE8E8E8)}) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0;
    final cy = y.toDouble();
    canvas.drawLine(
      Offset(x.toDouble(), cy),
      Offset((x + width).toDouble(), cy),
      paint,
    );
  }

  /// 绘制代码块占位符卡片（紧凑卡片：图标 + 语言 + 行数，点击后弹窗查看完整代码）
  void drawCodeBlock({
    required Rect rect,
    required TextCodeBlockElement element,
  }) {
    const bgColor = Color(0xFFF6F8FA);
    const borderColor = Color(0xFFE1E4E8);
    const iconColor = Color(0xFF6A737D);
    const langColor = Color(0xFF24292E);
    const infoColor = Color(0xFF959DA5);
    const radius = Radius.circular(8.0);

    // 1. 圆角背景 + 边框
    final rrect = RRect.fromRectAndRadius(rect, radius);
    canvas.drawRRect(rrect, Paint()..color = bgColor..style = PaintingStyle.fill);
    canvas.drawRRect(rrect, Paint()..color = borderColor..style = PaintingStyle.stroke..strokeWidth = 1.0);

    final centerY = rect.top + rect.height / 2;
    var curX = rect.left + 14.0;

    // 2. 代码图标 「</>」
    final iconPainter = TextPainter(
      text: const TextSpan(
        text: '</>',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: iconColor, fontFamily: 'monospace'),
      ),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
    )..layout();
    iconPainter.paint(canvas, Offset(curX, centerY - iconPainter.height / 2));
    curX += iconPainter.width + 10;
    iconPainter.dispose();

    // 3. 语言标签
    final langText = element.language != null && element.language!.isNotEmpty
        ? element.language!
        : 'Code';
    final langPainter = TextPainter(
      text: TextSpan(
        text: langText,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: langColor),
      ),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
    )..layout();
    langPainter.paint(canvas, Offset(curX, centerY - langPainter.height / 2));
    curX += langPainter.width;
    langPainter.dispose();

    // 4. 行数信息（右侧）
    final infoText = '${element.lines.length} 行  点击查看 >';
    final infoPainter = TextPainter(
      text: TextSpan(
        text: infoText,
        style: const TextStyle(fontSize: 12, color: infoColor),
      ),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final infoX = rect.right - 14.0 - infoPainter.width;
    infoPainter.paint(canvas, Offset(infoX, centerY - infoPainter.height / 2));
    infoPainter.dispose();
  }

  /// 绘制表格（微信公众号风格）
  void drawTable({
    required Rect rect,
    required TextTableElement element,
    required List<double> colWidths,
  }) {
    // 微信公众号风格配色
    const headerBgColor = Color(0xFFF2F3F5);    // 表头蓝灰背景
    const oddRowBgColor = Color(0xFFFFFFFF);     // 奇数行白色
    const evenRowBgColor = Color(0xFFFAFBFC);    // 偶数行浅灰
    const borderColor = Color(0xFFE5E5E5);       // 边框
    const textColor = Color(0xFF333333);          // 文字
    const headerTextColor = Color(0xFF1A1A1A);   // 表头文字
    const tableFontSize = 13.5;

    final borderPaint = Paint()..color = borderColor..strokeWidth = 1.0;
    final rowH = (rect.height - (element.totalRowCount + 1)) / element.totalRowCount;

    // 1. 绘制整体背景（圆角裁剪）
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(
      rect, const Radius.circular(TextTableElement.borderRadius),
    ));

    double curY = rect.top;
    for (int r = 0; r < element.totalRowCount; r++) {
      final isHeader = r == 0;

      // 行背景
      final rowBg = isHeader
          ? headerBgColor
          : (r % 2 == 1 ? oddRowBgColor : evenRowBgColor);
      canvas.drawRect(
        Rect.fromLTWH(rect.left, curY, rect.width, rowH + 1),
        Paint()..color = rowBg..style = PaintingStyle.fill,
      );

      // 行内容
      double curX = rect.left;
      final cells = isHeader ? element.headers : element.rows[r - 1];
      for (int c = 0; c < element.columnCount; c++) {
        final cellW = c < colWidths.length ? colWidths[c] : 60.0;
        final cellText = c < cells.length ? cells[c] : '';

        final painter = TextPainter(
          text: TextSpan(
            text: cellText,
            style: TextStyle(
              fontSize: tableFontSize,
              color: isHeader ? headerTextColor : textColor,
              fontWeight: isHeader ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          textDirection: ui.TextDirection.ltr,
          maxLines: 1,
          ellipsis: '...',
        )..layout(maxWidth: cellW - TextTableElement.cellPaddingH * 2);

        final align = c < element.alignments.length ? element.alignments[c] : 0;
        double textX;
        switch (align) {
          case TableAlignment.center:
            textX = curX + (cellW - painter.width) / 2;
            break;
          case TableAlignment.right:
            textX = curX + cellW - TextTableElement.cellPaddingH - painter.width;
            break;
          default:
            textX = curX + TextTableElement.cellPaddingH;
        }

        painter.paint(canvas, Offset(textX, curY + (rowH - painter.height) / 2));
        painter.dispose();

        // 垂直分割线（最后一列不画）
        if (c < element.columnCount - 1) {
          canvas.drawLine(
            Offset(curX + cellW, curY),
            Offset(curX + cellW, curY + rowH + 1),
            borderPaint,
          );
        }

        curX += cellW;
      }

      // 水平分割线
      canvas.drawLine(
        Offset(rect.left, curY + rowH + 1),
        Offset(rect.right, curY + rowH + 1),
        borderPaint,
      );

      curY += rowH + 1;
    }

    canvas.restore();

    // 2. 绘制圆角外边框
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(TextTableElement.borderRadius)),
      Paint()..color = borderColor..style = PaintingStyle.stroke..strokeWidth = 1.0,
    );
  }

  /// 绘制复选框（任务列表）
  void drawCheckbox(int x, int y, bool checked, {int size = TextCheckboxElement.size}) {
    final rect = Rect.fromLTWH(
      x.toDouble(),
      y.toDouble() - size,
      size.toDouble(),
      size.toDouble(),
    );

    // 边框
    final borderPaint = Paint()
      ..color = checked ? const Color(0xFF1a73e8) : const Color(0xFFCCCCCC)
      ..style = checked ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      borderPaint,
    );

    // 勾选标记
    if (checked) {
      final checkPaint = Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;
      final path = Path()
        ..moveTo(rect.left + 3, rect.top + size / 2)
        ..lineTo(rect.left + size / 2.5, rect.bottom - 3)
        ..lineTo(rect.right - 3, rect.top + 4);
      canvas.drawPath(path, checkPaint);
    }
  }
}
