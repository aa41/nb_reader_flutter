import 'package:flutter/rendering.dart';

import 'page_animation.dart';

/// 动画绘制器 - 代理给 PageAnimation
class AnimPagePainter extends CustomPainter {
  final PageAnimation animation;
  final int version;

  AnimPagePainter({
    required this.animation,
    required this.version,
  });

  @override
  void paint(Canvas canvas, Size size) {
    animation.draw(canvas, size, version);
  }

  @override
  bool shouldRepaint(covariant AnimPagePainter oldDelegate) {
    return oldDelegate.version != version ||
        !identical(oldDelegate.animation, animation);
  }
}
