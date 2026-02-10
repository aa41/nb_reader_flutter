import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'page_animation.dart';

/// 滑动翻页动画 - 两页并排滑动
/// 对应 Kotlin SlidePageAnimation.kt
class SlidePageAnimation extends PageAnimation {
  SlidePageAnimation({
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
      // 向左滑: 当前页向左移, 下一页从右侧进入
      final shift = offset.clamp(-w, 0.0);

      // 绘制当前页(向左偏移)
      if (fromPic != null) {
        canvas.save();
        canvas.clipRect(Rect.fromLTWH(0, 0, w + shift, h));
        canvas.translate(shift, 0);
        canvas.drawPicture(fromPic);
        canvas.restore();
      }

      // 绘制下一页(从右侧进入)
      if (toPic != null) {
        canvas.save();
        canvas.clipRect(Rect.fromLTWH(w + shift, 0, -shift, h));
        canvas.translate(w + shift, 0);
        canvas.drawPicture(toPic);
        canvas.restore();
      }

      // 分界线阴影
      _drawShadow(canvas, w + shift, h, true);
    } else if (direction == PageDirection.previous) {
      // 向右滑: 上一页从左侧进入, 当前页向右移
      final shift = offset.clamp(0.0, w);

      // 绘制上一页(从左侧进入)
      if (toPic != null) {
        canvas.save();
        canvas.clipRect(Rect.fromLTWH(0, 0, shift, h));
        canvas.translate(shift - w, 0);
        canvas.drawPicture(toPic);
        canvas.restore();
      }

      // 绘制当前页(向右偏移)
      if (fromPic != null) {
        canvas.save();
        canvas.clipRect(Rect.fromLTWH(shift, 0, w - shift, h));
        canvas.translate(shift, 0);
        canvas.drawPicture(fromPic);
        canvas.restore();
      }

      // 分界线阴影
      _drawShadow(canvas, shift, h, false);
    }
  }

  void _drawShadow(Canvas canvas, double x, double h, bool leftSide) {
    const shadowWidth = 16.0;
    final rect = leftSide
        ? Rect.fromLTWH(x - shadowWidth, 0, shadowWidth, h)
        : Rect.fromLTWH(x, 0, shadowWidth, h);

    final colors = leftSide
        ? [Colors.transparent, Colors.black26]
        : [Colors.black26, Colors.transparent];

    final paint = Paint()
      ..shader = ui.Gradient.linear(
        rect.centerLeft,
        rect.centerRight,
        colors,
      );
    canvas.drawRect(rect, paint);
  }
}
