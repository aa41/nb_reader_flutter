import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../page_enum.dart';

/// 翻页方向
enum PageDirection {
  none,
  previous,
  next,
}

/// 动画状态
enum AnimStatus {
  idle,       // 空闲
  manual,     // 手动拖拽中
  autoForward,  // 自动前进(完成翻页)
  autoBackward, // 自动回退(取消翻页)
}

/// 翻页回调
abstract class PageAnimCallback {
  /// 是否有指定方向的页面
  bool hasPage(PageType type);

  /// 执行翻页
  void turnPage(PageType type);

  /// 绘制指定类型的页面到 Canvas
  void drawPage(Canvas canvas, PageType type);

  /// 绘制页面覆盖层（搜索高亮等）——仅在空闲状态由动画系统调用
  void drawPageOverlay(Canvas canvas);

  /// 请求重绘
  void invalidate();
}

/// 翻页动画基类
/// 对应 Kotlin PageAnimation.kt
abstract class PageAnimation {
  final TickerProvider vsync;
  final PageAnimCallback callback;

  @protected
  late AnimationController animController;
  Animation<double>? _animation;

  /// 视口尺寸
  int viewWidth = 0;
  int viewHeight = 0;

  /// 方向与状态
  PageDirection direction = PageDirection.none;
  AnimStatus status = AnimStatus.idle;

  /// 触摸坐标
  double startX = 0;
  double touchX = 0;
  double lastX = 0;

  /// 缓存的 Picture
  ui.Picture? _curPicture;
  ui.Picture? _prevPicture;
  ui.Picture? _nextPicture;

  PageAnimation({
    required this.vsync,
    required this.callback,
  }) {
    animController = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 300),
    );
    animController.addListener(onAnimUpdate);
    animController.addStatusListener(_onAnimStatusChanged);
  }

  /// 设置视口
  void setViewPort(int width, int height) {
    if (viewWidth == width && viewHeight == height) return;
    viewWidth = width;
    viewHeight = height;
    invalidateCache();
  }

  // === 手势处理 ===

  void onPanStart(DragStartDetails details) {
    if (status != AnimStatus.idle) return;
    startX = details.localPosition.dx;
    touchX = startX;
    lastX = startX;
    direction = PageDirection.none;
    status = AnimStatus.manual;
  }

  void onPanUpdate(DragUpdateDetails details) {
    if (status != AnimStatus.manual) return;
    lastX = touchX;
    touchX = details.localPosition.dx;

    // 首次移动时确定方向
    if (direction == PageDirection.none) {
      final dx = touchX - startX;
      if (dx.abs() < 2) return; // 太小不算
      if (dx > 0) {
        direction = PageDirection.previous;
        if (!callback.hasPage(PageType.previous)) {
          _cancelDrag();
          return;
        }
      } else {
        direction = PageDirection.next;
        if (!callback.hasPage(PageType.next)) {
          _cancelDrag();
          return;
        }
      }
    }

    callback.invalidate();
  }

  void onPanEnd(DragEndDetails details) {
    if (status != AnimStatus.manual || direction == PageDirection.none) {
      _cancelDrag();
      return;
    }

    final dx = touchX - startX;
    final velocity = details.velocity.pixelsPerSecond.dx;

    // 判断是否完成翻页: 滑动超过 1/3 或速度足够
    bool shouldComplete;
    if (direction == PageDirection.next) {
      shouldComplete = dx < -viewWidth / 3 || velocity < -300;
    } else {
      shouldComplete = dx > viewWidth / 3 || velocity > 300;
    }

    if (shouldComplete) {
      _startAutoForward();
    } else {
      _startAutoBackward();
    }
  }

  /// 点击翻页(无拖拽)
  void startTapAnim(PageDirection dir) {
    if (status != AnimStatus.idle) return;
    if (dir == PageDirection.none) return;

    final pageType =
        dir == PageDirection.next ? PageType.next : PageType.previous;
    if (!callback.hasPage(pageType)) return;

    direction = dir;
    startX = dir == PageDirection.next ? viewWidth.toDouble() : 0;
    touchX = startX;
    _startAutoForward();
  }

  void _cancelDrag() {
    status = AnimStatus.idle;
    direction = PageDirection.none;
    callback.invalidate();
  }

  void _startAutoForward() {
    status = AnimStatus.autoForward;
    final begin = _getAnimProgress();
    _animation = Tween<double>(begin: begin, end: 1.0).animate(
      CurvedAnimation(parent: animController, curve: Curves.easeOut),
    );
    animController.forward(from: 0);
  }

  void _startAutoBackward() {
    status = AnimStatus.autoBackward;
    final begin = _getAnimProgress();
    _animation = Tween<double>(begin: begin, end: 0.0).animate(
      CurvedAnimation(parent: animController, curve: Curves.easeOut),
    );
    animController.forward(from: 0);
  }

  @protected
  void onAnimUpdate() {
    if (_animation == null) return;
    final progress = _animation!.value;
    // 将 progress 转换为 touchX
    touchX = _progressToTouchX(progress);
    callback.invalidate();
  }

  void _onAnimStatusChanged(AnimationStatus animStatus) {
    if (animStatus == AnimationStatus.completed) {
      _finishAnim();
    }
  }

  void _finishAnim() {
    if (status == AnimStatus.autoForward) {
      // 翻页成功
      final pageType = direction == PageDirection.next
          ? PageType.next
          : PageType.previous;
      callback.turnPage(pageType);
      invalidateCache();
    }
    status = AnimStatus.idle;
    direction = PageDirection.none;
    _animation = null;
    animController.reset();
    callback.invalidate();
  }

  // === 动画进度计算 ===

  /// 当前拖拽对应的动画进度 [0, 1]
  double _getAnimProgress() {
    if (viewWidth == 0) return 0;
    final dx = (touchX - startX).abs();
    return (dx / viewWidth).clamp(0.0, 1.0);
  }

  /// 将动画进度转换回 touchX
  double _progressToTouchX(double progress) {
    if (direction == PageDirection.next) {
      return startX - progress * viewWidth;
    } else {
      return startX + progress * viewWidth;
    }
  }

  // === Picture 缓存 ===

  void invalidateCache() {
    _curPicture?.dispose();
    _prevPicture?.dispose();
    _nextPicture?.dispose();
    _curPicture = null;
    _prevPicture = null;
    _nextPicture = null;
  }

  void _ensureCache(int version) {
    // 仅在缓存被 invalidate 后才重新录制
    if (_curPicture != null) return;
    _curPicture = _recordPage(PageType.current);

    if (callback.hasPage(PageType.previous)) {
      _prevPicture?.dispose();
      _prevPicture = _recordPage(PageType.previous);
    }
    if (callback.hasPage(PageType.next)) {
      _nextPicture?.dispose();
      _nextPicture = _recordPage(PageType.next);
    }
  }

  ui.Picture _recordPage(PageType type) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder,
        Rect.fromLTWH(0, 0, viewWidth.toDouble(), viewHeight.toDouble()));
    callback.drawPage(canvas, type);
    return recorder.endRecording();
  }

  /// 获取"来源页"的 Picture (当前页)
  ui.Picture? getFromPicture() => _curPicture;

  /// 获取"目标页"的 Picture
  ui.Picture? getToPicture() {
    if (direction == PageDirection.next) return _nextPicture;
    if (direction == PageDirection.previous) return _prevPicture;
    return null;
  }

  // === 绘制 ===

  /// 绘制入口
  void draw(Canvas canvas, Size size, int version) {
    _ensureCache(version);

    if (status == AnimStatus.idle || direction == PageDirection.none) {
      drawStatic(canvas, size);
    } else {
      drawMove(canvas, size);
    }
  }

  /// 静态绘制(空闲时)
  void drawStatic(Canvas canvas, Size size) {
    final pic = _curPicture;
    if (pic != null) {
      canvas.drawPicture(pic);
    }
    // 绘制搜索高亮等覆盖层（独立于 Picture 缓存，实时绘制）
    callback.drawPageOverlay(canvas);
  }

  /// 动态绘制(拖拽/动画中) - 子类实现
  void drawMove(Canvas canvas, Size size);

  // === 生命周期 ===

  void dispose() {
    animController.dispose();
    invalidateCache();
  }

  /// 是否处于动画中
  bool get isAnimating =>
      status == AnimStatus.autoForward || status == AnimStatus.autoBackward;

  /// 是否处于拖拽中
  bool get isDragging => status == AnimStatus.manual;

  /// 是否空闲
  bool get isIdle => status == AnimStatus.idle;
}
