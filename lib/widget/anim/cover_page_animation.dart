import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'page_animation.dart';

/// 覆盖翻页动画 - 新页覆盖在旧页上方
/// 对应 Kotlin CoverPageAnimation.kt
class CoverPageAnimation extends PageAnimation {
  CoverPageAnimation({
    required super.vsync,
    required super.callback,
  });

  @override
  void drawMove(Canvas canvas, Size size) {
    final w = viewWidth.toDouble();
    final h = viewHeight.toDouble();
    final offset = touchX - startX;

    final fromPic = getFromPicture();
    final toPic = getToPicture();

    if (direction == PageDirection.next) {
      // 向左滑: 下一页不动(底层), 当前页向左滑出(上层)
      final shift = offset.clamp(-w, 0.0);

      // 底层: 下一页(全屏)
      if (toPic != null) {
        canvas.drawPicture(toPic);
      }

      // 上层: 当前页 从右往左滑出
      if (fromPic != null) {
        canvas.save();
        canvas.clipRect(Rect.fromLTWH(0, 0, w + shift, h));
        canvas.drawPicture(fromPic);
        canvas.restore();
      }

      // 阴影在当前页右边缘
      _drawEdgeShadow(canvas, w + shift, h);
    } else if (direction == PageDirection.previous) {
      // 向右滑: 当前页不动(底层), 上一页从左侧滑入(上层)
      final shift = offset.clamp(0.0, w);

      // 底层: 当前页(全屏)
      if (fromPic != null) {
        canvas.drawPicture(fromPic);
      }

      // 上层: 上一页 从左往右滑入
      if (toPic != null) {
        canvas.save();
        canvas.clipRect(Rect.fromLTWH(0, 0, shift, h));
        canvas.translate(shift - w, 0);
        canvas.drawPicture(toPic);
        canvas.restore();
      }

      // 阴影在上一页右边缘
      _drawEdgeShadow(canvas, shift, h);
    }
  }

  void _drawEdgeShadow(Canvas canvas, double x, double h) {
    const shadowWidth = 24.0;
    final rect = Rect.fromLTWH(x, 0, shadowWidth, h);

    final paint = Paint()
      ..shader = ui.Gradient.linear(
        rect.centerLeft,
        rect.centerRight,
        [Colors.black38, Colors.transparent],
      );
    canvas.drawRect(rect, paint);
  }
}
