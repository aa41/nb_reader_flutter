import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../element/text_image_element.dart';
import 'text_paint_context.dart';

/// 图片解码缓存（全局单例）
class _ImageDecodeCache {
  static final _ImageDecodeCache instance = _ImageDecodeCache._();
  _ImageDecodeCache._();

  final Map<String, ui.Image?> _cache = {};
  final Set<String> _loading = {};
  VoidCallback? onImageDecoded;

  /// 获取已解码的图片，如果未解码则异步解码并返回 null
  ui.Image? get(String key, Uint8List? data) {
    if (_cache.containsKey(key)) return _cache[key];
    if (_loading.contains(key) || data == null) return null;
    _loading.add(key);
    _decodeAsync(key, data);
    return null;
  }

  Future<void> _decodeAsync(String key, Uint8List data) async {
    try {
      final codec = await ui.instantiateImageCodec(data);
      final frame = await codec.getNextFrame();
      _cache[key] = frame.image;
      codec.dispose();
      _loading.remove(key);
      onImageDecoded?.call();
    } catch (_) {
      _cache[key] = null;
      _loading.remove(key);
    }
  }
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
}
