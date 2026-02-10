import 'package:flutter/material.dart';

import '../page_enum.dart';
import 'page_animation.dart';

/// 无动画翻页 - 直接切换
/// 对应 Kotlin NonePageAnimation.kt
class NonePageAnimation extends PageAnimation {
  NonePageAnimation({
    required super.vsync,
    required super.callback,
  });

  @override
  void drawMove(Canvas canvas, Size size) {
    // 无动画, 直接绘制当前页
    drawStatic(canvas, size);
  }

  @override
  void startTapAnim(PageDirection dir) {
    if (dir == PageDirection.none) return;
    final pageType =
        dir == PageDirection.next ? PageType.next : PageType.previous;
    if (!callback.hasPage(pageType)) return;

    // 直接翻页, 不播放动画
    callback.turnPage(pageType);
    invalidateCache();
    callback.invalidate();
  }

  @override
  void onPanEnd(DragEndDetails details) {
    if (status != AnimStatus.manual || direction == PageDirection.none) {
      status = AnimStatus.idle;
      direction = PageDirection.none;
      callback.invalidate();
      return;
    }

    // 拖拽超过 1/4 即翻页
    final dx = touchX - startX;
    bool shouldTurn;
    if (direction == PageDirection.next) {
      shouldTurn = dx < -viewWidth / 4;
    } else {
      shouldTurn = dx > viewWidth / 4;
    }

    if (shouldTurn) {
      final pageType = direction == PageDirection.next
          ? PageType.next
          : PageType.previous;
      callback.turnPage(pageType);
      invalidateCache();
    }

    status = AnimStatus.idle;
    direction = PageDirection.none;
    callback.invalidate();
  }
}
