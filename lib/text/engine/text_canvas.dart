import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

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
    if (_loading.contains(key)) return null;

    // 有数据直接解码
    if (data != null) {
      _loading.add(key);
      _decodeAsync(key, data);
      return null;
    }

    // 网络图片：下载后再解码
    if (key.startsWith('http://') || key.startsWith('https://')) {
      _loading.add(key);
      _downloadAndDecode(key);
      return null;
    }

    return null;
  }

  Future<void> _downloadAndDecode(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        await _decodeAsync(url, response.bodyBytes);
      } else {
        _cache[url] = null;
        _loading.remove(url);
      }
    } catch (_) {
      _cache[url] = null;
      _loading.remove(url);
    }
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

  /// 绘制图片（固定高度 + 居中显示）
  void drawImage(int x, int y, TextImage image, Size textAreaSize) {
    final layoutSize = paintContext.getImageSize(image, textAreaSize);
    if (layoutSize == null) return;

    final fixedH = layoutSize.height;
    final areaW = layoutSize.width;

    // 尝试从缓存获取解码后的图片
    final decoded = _ImageDecodeCache.instance.get(image.id, image.data);
    if (decoded != null) {
      image.decodedImage ??= decoded;

      // 按固定高度计算实际渲染宽度（保持原始宽高比）
      final origW = decoded.width.toDouble();
      final origH = decoded.height.toDouble();
      var renderW = origW * (fixedH / origH);
      var renderH = fixedH;
      // 如果宽度超出文本区域，则按宽度缩放
      if (renderW > areaW) {
        renderW = areaW;
        renderH = origH * (areaW / origW);
      }

      // 水平居中
      final offsetX = x.toDouble() + (areaW - renderW) / 2;
      final offsetY = y.toDouble() - fixedH + (fixedH - renderH) / 2;

      final dst = Rect.fromLTWH(offsetX, offsetY, renderW, renderH);
      final src = Rect.fromLTWH(0, 0, origW, origH);
      canvas.drawImageRect(decoded, src, dst, Paint());
    } else {
      // 占位框（居中显示）
      final placeholderW = fixedH * 0.75; // 默认 4:3 占位
      final offsetX = x.toDouble() + (areaW - placeholderW) / 2;
      final offsetY = y.toDouble() - fixedH + (fixedH - fixedH * 0.6) / 2;
      final rect = Rect.fromLTWH(offsetX, offsetY, placeholderW, fixedH * 0.6);
      canvas.drawRect(rect, Paint()..color = const Color(0xFFF0F0F0));
      canvas.drawRect(
        rect,
        Paint()
          ..color = const Color(0xFFCCCCCC)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }
}
