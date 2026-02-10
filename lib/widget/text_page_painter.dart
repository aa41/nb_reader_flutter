import 'package:flutter/rendering.dart';

import '../text/engine/text_engine.dart';
import 'page_enum.dart';

/// 文本页面绘制器 - CustomPainter
/// 使用 TextEngine 将文本绘制到 Flutter Canvas 上
class TextPagePainter extends CustomPainter {
  final TextEngine engine;
  final PageType pageType;
  final int version;

  TextPagePainter({
    required this.engine,
    this.pageType = PageType.current,
    this.version = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    engine.draw(canvas, pageType);
  }

  @override
  bool shouldRepaint(covariant TextPagePainter oldDelegate) {
    return oldDelegate.version != version || oldDelegate.pageType != pageType;
  }
}
