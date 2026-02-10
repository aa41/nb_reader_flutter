import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../page_enum.dart';
import 'page_animation.dart';

/// 滚动动画 - 连续垂直滚动
/// 对应 Kotlin ScrollPageAnimation.kt
///
/// 与其他翻页动画不同，滚动动画不是离散的"翻一页"，而是连续滚动。
/// 使用 [_PageLayout] 管理 2 个页面在视口中的垂直位置，
/// 当一页滚出视口时回收并动态填充新页面。
class ScrollPageAnimation extends PageAnimation {
  // 触摸坐标
  int _touchX = 0;
  int _touchY = 0;
  int _lastY = 0;

  // 页面布局数组(2个，循环使用)
  final _pageLayouts = [_PageLayout(), _PageLayout()];

  // 滚动状态(独立于基类的 status)
  _Status _scrollStatus = _Status.none;

  // Picture 缓存(独立于基类，按 PageType 缓存)
  final Map<PageType, ui.Picture> _pictures = {};

  ScrollPageAnimation({
    required super.vsync,
    required super.callback,
  }) {
    // 替换基类的 AnimationController 为无边界版本
    // fling 模拟的 Y 坐标值远超 [0,1] 范围
    animController.dispose();
    animController = AnimationController.unbounded(vsync: vsync);
    animController.addListener(_onFlingTick);
    animController.addStatusListener(_onFlingStatus);
  }

  bool get _isRunning => _scrollStatus != _Status.none;

  /// 获取竖直滑动距离(帧间增量)
  int get _scrollY => _isRunning ? _touchY - _lastY : 0;

  // ========== 重写状态查询 ==========

  @override
  bool get isAnimating => _scrollStatus == _Status.fling;

  @override
  bool get isDragging =>
      _scrollStatus == _Status.press || _scrollStatus == _Status.move;

  @override
  bool get isIdle => _scrollStatus == _Status.none;

  // ========== 视口设置 ==========

  @override
  void setViewPort(int width, int height) {
    if (width == 0 || height == 0) return;
    if (viewWidth == width && viewHeight == height) return;
    viewWidth = width;
    viewHeight = height;
    _abortAnim();
    for (final layout in _pageLayouts) {
      layout.setHeight(height);
    }
    _invalidatePictures();
    _layout();
  }

  // ========== 手势处理 ==========

  @override
  void onPanStart(DragStartDetails details) {
    // 如果正在 fling，先中止
    if (_scrollStatus == _Status.fling) {
      _abortAnim();
    }

    final x = details.localPosition.dx.toInt();
    final y = details.localPosition.dy.toInt();
    _touchX = x;
    _touchY = y;
    _lastY = y;
    _scrollStatus = _Status.press;
  }

  @override
  void onPanUpdate(DragUpdateDetails details) {
    // 如果状态异常，当作 press 重新开始
    if (_scrollStatus == _Status.none || _scrollStatus == _Status.fling) {
      onPanStart(DragStartDetails(
        localPosition: details.localPosition,
        globalPosition: details.globalPosition,
      ));
    }

    final x = details.localPosition.dx.toInt();
    final y = details.localPosition.dy.toInt();
    _setTouchPoint(x, y);
    _scrollStatus = _Status.move;
    callback.invalidate();
  }

  @override
  void onPanEnd(DragEndDetails details) {
    if (_scrollStatus == _Status.none) return;

    // 使用 Flutter GestureDetector 提供的速度(等价于 VelocityTracker)
    final velocityY = details.velocity.pixelsPerSecond.dy;
    _startFling(velocityY);
  }

  void _setTouchPoint(int x, int y) {
    _lastY = _touchY;
    _touchX = x;
    _touchY = y;
  }

  // ========== Fling 惯性动画 ==========

  void _startFling(double velocity) {
    _scrollStatus = _Status.fling;
    // ClampingScrollSimulation 模拟 Android Scroller.fling 的减速效果
    animController.animateWith(
      ClampingScrollSimulation(
        position: _touchY.toDouble(),
        velocity: velocity,
      ),
    );
  }

  void _onFlingTick() {
    if (_scrollStatus != _Status.fling) return;
    final y = animController.value.toInt();
    _setTouchPoint(_touchX, y);
    callback.invalidate();
  }

  void _onFlingStatus(AnimationStatus animStatus) {
    if (animStatus == AnimationStatus.completed ||
        animStatus == AnimationStatus.dismissed) {
      _finishScroll();
    }
  }

  void _abortAnim() {
    if (animController.isAnimating) {
      animController.stop();
    }
    _finishScroll();
  }

  void _finishScroll() {
    _scrollStatus = _Status.none;
    // 延迟 invalidate，避免在 paint 期间触发 setState
    // (_fillDown/_fillUp 可能在 draw() 中调用 _abortAnim)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      callback.invalidate();
    });
  }

  // ========== 布局逻辑 ==========

  /// 根据滚动方向进行布局
  void _layout() {
    final scrollY = _scrollY;
    if (scrollY > 0) {
      _fillUp(scrollY);
    } else {
      _fillDown(scrollY);
    }
  }

  /// 向上滑动(scrollY <= 0)，内容上移，填充底部空白
  void _fillDown(int scrollY) {
    bool hasTurnPage = false;

    for (final layout in _pageLayouts) {
      if (layout.type == null) continue;
      layout.offset(scrollY);
      // 页面完全滑出视口顶部
      if (layout.bottom <= 0) {
        layout.reset();
        callback.turnPage(PageType.next);
        _invalidatePictures();
        hasTurnPage = true;
      }
    }

    // 翻页后更新所有布局类型: NEXT→CURRENT, CURRENT→PREVIOUS
    if (hasTurnPage) {
      _turnPageLayout(PageType.next);
    }

    // 确保 current 页布局存在
    if (_getPageLayout(PageType.current) == null &&
        callback.hasPage(PageType.current)) {
      final newLayout = _getScrapLayout();
      if (newLayout != null) {
        newLayout.type = PageType.current;
      }
    }

    // 检测底部空白区域
    final pageBottom = _getPageBottom();
    final fillArea = pageBottom == null
        ? viewHeight
        : (viewHeight - pageBottom).clamp(0, viewHeight);

    if (fillArea > 0) {
      if (callback.hasPage(PageType.next)) {
        // 在底部添加下一页
        final layout = _getScrapLayout();
        if (layout != null) {
          layout.type = PageType.next;
          layout.offset(viewHeight - fillArea);
        }
      } else {
        // 没有下一页，重置为当前页并停止动画
        if (_hasActiveLayout()) {
          _clearLayouts();
          final layout = _getScrapLayout();
          if (layout != null) {
            layout.type = PageType.current;
          }
        }
        _abortAnim();
      }
    }
  }

  /// 向下滑动(scrollY > 0)，内容下移，填充顶部空白
  void _fillUp(int scrollY) {
    bool hasTurnPage = false;

    for (final layout in _pageLayouts) {
      if (layout.type == null) continue;
      layout.offset(scrollY);
      // 页面完全滑出视口底部
      if (layout.top >= viewHeight) {
        layout.reset();
        if (callback.hasPage(PageType.previous)) {
          callback.turnPage(PageType.previous);
          _invalidatePictures();
          hasTurnPage = true;
        }
      }
    }

    // 翻页后更新所有布局类型: PREVIOUS→CURRENT, CURRENT→NEXT
    if (hasTurnPage) {
      _turnPageLayout(PageType.previous);
    }

    // 确保 current 页布局存在
    if (_getPageLayout(PageType.current) == null &&
        callback.hasPage(PageType.current)) {
      final pageTop = _getPageTop();
      final newLayout = _getScrapLayout();
      if (newLayout != null) {
        newLayout.type = PageType.current;
        if (pageTop != null) {
          newLayout.offset(pageTop - viewHeight);
        }
      }
    }

    // 检测顶部空白区域
    final pageTop = _getPageTop();
    final fillArea =
        pageTop == null ? viewHeight : pageTop.clamp(0, viewHeight);

    if (fillArea > 0) {
      if (callback.hasPage(PageType.previous)) {
        // 在顶部添加上一页
        final layout = _getScrapLayout();
        if (layout != null) {
          layout.type = PageType.previous;
          layout.offset(fillArea - viewHeight);
          // 上一页加入后立即翻页，使其成为 current
          callback.turnPage(PageType.previous);
          _invalidatePictures();
          _turnPageLayout(PageType.previous);
        }
      } else {
        // 没有上一页，重置为当前页并停止动画
        if (_hasActiveLayout()) {
          _clearLayouts();
          final layout = _getScrapLayout();
          if (layout != null) {
            layout.type = PageType.current;
          }
        }
        _abortAnim();
      }
    }
  }

  // ========== Layout 辅助方法 ==========

  /// 翻页后更新布局类型
  /// [type] == NEXT: 所有类型向前移一位 (NEXT→CURRENT, CURRENT→PREVIOUS)
  /// [type] == PREVIOUS: 所有类型向后移一位 (PREVIOUS→CURRENT, CURRENT→NEXT)
  void _turnPageLayout(PageType type) {
    for (final layout in _pageLayouts) {
      if (layout.type == null) continue;
      if (type == PageType.previous) {
        layout.type = layout.type!.getNext();
      } else if (type == PageType.next) {
        layout.type = layout.type!.getPrevious();
      }
    }
  }

  _PageLayout? _getPageLayout(PageType type) {
    for (final layout in _pageLayouts) {
      if (layout.type == type) return layout;
    }
    return null;
  }

  _PageLayout? _getScrapLayout() {
    for (final layout in _pageLayouts) {
      if (layout.type == null) return layout;
    }
    return null;
  }

  bool _hasActiveLayout() {
    for (final layout in _pageLayouts) {
      if (layout.type != null) return true;
    }
    return false;
  }

  void _clearLayouts() {
    for (final layout in _pageLayouts) {
      layout.reset();
    }
  }

  int? _getPageTop() {
    int? result;
    for (final layout in _pageLayouts) {
      if (layout.type == null) continue;
      if (result == null || layout.top < result) {
        result = layout.top;
      }
    }
    return result;
  }

  int? _getPageBottom() {
    int? result;
    for (final layout in _pageLayouts) {
      if (layout.type == null) continue;
      if (result == null || layout.bottom > result) {
        result = layout.bottom;
      }
    }
    return result;
  }

  // ========== 绘制 ==========

  /// 完全重写绘制入口，不使用基类的 Picture 缓存
  @override
  void draw(Canvas canvas, Size size, int version) {
    if (_isRunning) {
      _drawMove(canvas);
    } else {
      _drawStatic(canvas);
    }
  }

  /// 动态绘制: 先布局再绘制
  void _drawMove(Canvas canvas) {
    _layout();
    _drawPages(canvas);
  }

  /// 静态绘制: 确保有布局后绘制
  void _drawStatic(Canvas canvas) {
    if (!_hasActiveLayout()) {
      _layout();
    }
    _drawPages(canvas);
  }

  /// 遍历所有活跃布局，在对应 Y 偏移处绘制页面
  void _drawPages(Canvas canvas) {
    final w = viewWidth.toDouble();
    final h = viewHeight.toDouble();

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, w, h));

    for (final layout in _pageLayouts) {
      if (layout.type == null) continue;
      // 只绘制 current 和 next (与 Kotlin 原版一致)
      if (layout.type == PageType.current || layout.type == PageType.next) {
        final pic = _ensurePicture(layout.type!);
        if (pic != null) {
          canvas.save();
          canvas.translate(0, layout.top.toDouble());
          canvas.drawPicture(pic);
          canvas.restore();
        }
      }
    }

    canvas.restore();
  }

  /// 按需录制 Picture，已有缓存则直接返回
  ui.Picture? _ensurePicture(PageType type) {
    if (!_pictures.containsKey(type)) {
      final recorder = ui.PictureRecorder();
      final c = Canvas(recorder,
          Rect.fromLTWH(0, 0, viewWidth.toDouble(), viewHeight.toDouble()));
      callback.drawPage(c, type);
      _pictures[type] = recorder.endRecording();
    }
    return _pictures[type];
  }

  void _invalidatePictures() {
    for (final pic in _pictures.values) {
      pic.dispose();
    }
    _pictures.clear();
  }

  /// 外部调用 invalidateCache 时也清理滚动缓存
  @override
  void invalidateCache() {
    super.invalidateCache();
    _invalidatePictures();
    _clearLayouts();
  }

  // ========== Tap 翻页 ==========

  @override
  void startTapAnim(PageDirection dir) {
    if (_scrollStatus == _Status.fling) {
      _abortAnim();
    }
    if (_scrollStatus != _Status.none) return;
    if (dir == PageDirection.none) return;

    final type =
        dir == PageDirection.next ? PageType.next : PageType.previous;
    if (!callback.hasPage(type)) return;

    // 以固定速度触发 fling，模拟点击翻页
    _touchY = viewHeight ~/ 2;
    _lastY = _touchY;
    final velocity =
        dir == PageDirection.next ? -viewHeight * 3.0 : viewHeight * 3.0;
    _startFling(velocity);
  }

  /// 基类抽象方法(不使用，由 draw() 直接分发)
  @override
  void drawMove(Canvas canvas, Size size) {}

  // ========== 生命周期 ==========

  @override
  void dispose() {
    _invalidatePictures();
    super.dispose();
  }
}

// ========== 内部类 ==========

/// 滚动状态
enum _Status {
  none, // 空闲
  press, // 手动按下
  move, // 手动滑动
  fling, // 惯性滑动
}

/// 页面布局 - 追踪页面在视口中的垂直位置
/// 对应 Kotlin PageLayout 内部类
class _PageLayout {
  /// Page Top 距离 ViewPort Top 的位置
  int top = 0;

  /// Page Bottom 距离 ViewPort Top 的位置
  int bottom = 0;

  int _height = 0;

  /// 当前布局针对的页面类型(null 表示空闲/可回收)
  PageType? type;

  void setHeight(int height) {
    _height = height;
    reset();
  }

  void offset(int y) {
    top += y;
    bottom += y;
  }

  void reset() {
    top = 0;
    bottom = _height;
    type = null;
  }
}
