import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../page_enum.dart';
import 'page_animation.dart';

/// 滚动动画 — 连续垂直滚动，行为类似原生 ScrollView。
///
/// 核心模型：用单一 [_pageOffset] 追踪当前页在视口中的垂直偏移（像素）：
///   _pageOffset == 0  → 当前页完全占满视口
///   _pageOffset < 0   → 向上滚动，下一页从底部进入
///   _pageOffset > 0   → 向下滚动，上一页从顶部进入
///
/// 偏移量超过一个视口高度时自动触发翻页并调整偏移，
/// 避免了旧实现中 delta 累积误差和双布局状态管理的复杂性。
class ScrollPageAnimation extends PageAnimation {
  // ==================== 滚动状态 ====================

  /// 当前页顶边相对于视口顶边的偏移（像素）
  double _pageOffset = 0;

  /// 上一次触摸 Y 坐标（计算帧间增量用）
  double _lastTouchY = 0;

  /// 上一帧 fling simulation 的输出值（计算帧间增量用）
  double _lastFlingValue = 0;

  /// 独立于基类的滚动状态机
  _ScrollStatus _status = _ScrollStatus.idle;

  // ==================== Picture 缓存 ====================

  final Map<PageType, ui.Picture> _pictureCache = {};

  ScrollPageAnimation({
    required super.vsync,
    required super.callback,
  }) {
    // 基类创建的 AnimationController 范围为 [0,1]，
    // fling simulation 值域远超此范围，替换为 unbounded 版本。
    animController.dispose();
    animController = AnimationController.unbounded(vsync: vsync);
    animController.addListener(_onFlingTick);
    animController.addStatusListener(_onFlingStatusChanged);
  }

  // ==================== 状态查询（重写基类） ====================

  @override
  bool get isAnimating => _status == _ScrollStatus.fling;

  @override
  bool get isDragging =>
      _status == _ScrollStatus.press || _status == _ScrollStatus.drag;

  @override
  bool get isIdle => _status == _ScrollStatus.idle;

  // ==================== 视口 ====================

  @override
  void setViewPort(int width, int height) {
    if (width == 0 || height == 0) return;
    if (viewWidth == width && viewHeight == height) return;
    viewWidth = width;
    viewHeight = height;
    _stopFlingImmediate();
    _pageOffset = 0;
    _disposePictures();
  }

  // ==================== 手势处理 ====================

  @override
  void onPanStart(DragStartDetails details) {
    // 中断正在进行的 fling
    if (_status == _ScrollStatus.fling) {
      _stopFlingImmediate();
    }
    _lastTouchY = details.localPosition.dy;
    _status = _ScrollStatus.press;
  }

  @override
  void onPanUpdate(DragUpdateDetails details) {
    // 从异常状态恢复
    if (_status == _ScrollStatus.idle || _status == _ScrollStatus.fling) {
      onPanStart(DragStartDetails(
        localPosition: details.localPosition,
        globalPosition: details.globalPosition,
      ));
    }

    final y = details.localPosition.dy;
    final delta = y - _lastTouchY;
    _lastTouchY = y;

    _status = _ScrollStatus.drag;
    _applyScrollDelta(delta);
    callback.invalidate();
  }

  @override
  void onPanEnd(DragEndDetails details) {
    if (_status == _ScrollStatus.idle) return;

    final vy = details.velocity.pixelsPerSecond.dy;
    // 速度太小直接停止，避免无意义的微弱惯性
    if (vy.abs() < 50.0) {
      _status = _ScrollStatus.idle;
      callback.invalidate();
      return;
    }
    _startFling(vy);
  }

  // ==================== 滚动核心逻辑 ====================

  /// 应用滚动增量，处理翻页与边界。
  /// 返回 true 表示已触及边界（调用方可据此停止 fling）。
  bool _applyScrollDelta(double delta) {
    final vh = viewHeight.toDouble();
    _pageOffset += delta;

    // --- 向上滚动（手指上滑，_pageOffset 减小）→ 翻到下一页 ---
    while (_pageOffset <= -vh) {
      if (!callback.hasPage(PageType.next)) {
        _pageOffset = 0;
        return true;
      }
      _pageOffset += vh;
      callback.turnPage(PageType.next);
      _shiftPicturesForward();
    }

    // --- 向下滚动（手指下滑，_pageOffset 增大）→ 翻到上一页 ---
    while (_pageOffset >= vh) {
      if (!callback.hasPage(PageType.previous)) {
        _pageOffset = 0;
        return true;
      }
      _pageOffset -= vh;
      callback.turnPage(PageType.previous);
      _shiftPicturesBackward();
    }

    // --- 边界钳制：无下一页时禁止向上滚动 ---
    if (_pageOffset < 0 && !callback.hasPage(PageType.next)) {
      _pageOffset = 0;
      return true;
    }

    // --- 边界钳制：无上一页时禁止向下滚动 ---
    if (_pageOffset > 0 && !callback.hasPage(PageType.previous)) {
      _pageOffset = 0;
      return true;
    }

    return false;
  }

  // ==================== Fling 惯性动画 ====================

  void _startFling(double velocity) {
    _status = _ScrollStatus.fling;
    _lastFlingValue = 0;
    // ClampingScrollSimulation 模拟 Android 原生减速曲线
    animController.animateWith(
      ClampingScrollSimulation(position: 0, velocity: velocity),
    );
  }

  void _onFlingTick() {
    if (_status != _ScrollStatus.fling) return;

    final cur = animController.value;
    final delta = cur - _lastFlingValue;
    _lastFlingValue = cur;

    final hitBoundary = _applyScrollDelta(delta);
    callback.invalidate();

    if (hitBoundary) {
      _stopFlingImmediate();
    }
  }

  void _onFlingStatusChanged(AnimationStatus s) {
    // 自然结束（simulation 跑完）
    if (s == AnimationStatus.completed || s == AnimationStatus.dismissed) {
      if (_status == _ScrollStatus.fling) {
        _status = _ScrollStatus.idle;
        callback.invalidate();
      }
    }
  }

  /// 立即中止 fling 动画并重置状态
  void _stopFlingImmediate() {
    if (animController.isAnimating) {
      animController.stop();
    }
    _status = _ScrollStatus.idle;
  }

  // ==================== 绘制 ====================

  /// 完全重写绘制入口，不使用基类的 Picture 缓存体系
  @override
  void draw(Canvas canvas, Size size, int version) {
    final w = viewWidth.toDouble();
    final h = viewHeight.toDouble();

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, w, h));

    // 绘制当前页
    final curPic = _ensurePicture(PageType.current);
    if (curPic != null) {
      canvas.save();
      canvas.translate(0, _pageOffset);
      canvas.drawPicture(curPic);
      canvas.restore();
    }

    // 空闲状态下绘制搜索高亮覆盖层
    if (_status == _ScrollStatus.idle && _pageOffset == 0) {
      callback.drawPageOverlay(canvas);
    }

    // 向上滚动（_pageOffset < 0）→ 在当前页下方绘制下一页
    if (_pageOffset < 0) {
      final nextPic = _ensurePicture(PageType.next);
      if (nextPic != null) {
        canvas.save();
        canvas.translate(0, _pageOffset + h);
        canvas.drawPicture(nextPic);
        canvas.restore();
      }
    }

    // 向下滚动（_pageOffset > 0）→ 在当前页上方绘制上一页
    if (_pageOffset > 0) {
      final prevPic = _ensurePicture(PageType.previous);
      if (prevPic != null) {
        canvas.save();
        canvas.translate(0, _pageOffset - h);
        canvas.drawPicture(prevPic);
        canvas.restore();
      }
    }

    canvas.restore();
  }

  /// 基类抽象方法（由 draw() 统一处理，此处不使用）
  @override
  void drawMove(Canvas canvas, Size size) {}

  // ==================== Picture 缓存 ====================

  /// 按需录制 Picture，已有缓存则直接返回
  ui.Picture? _ensurePicture(PageType type) {
    final cached = _pictureCache[type];
    if (cached != null) return cached;

    // 非 current 类型需确认页面存在
    if (type != PageType.current && !callback.hasPage(type)) return null;

    final recorder = ui.PictureRecorder();
    final c = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, viewWidth.toDouble(), viewHeight.toDouble()),
    );
    callback.drawPage(c, type);
    final pic = recorder.endRecording();
    _pictureCache[type] = pic;
    return pic;
  }

  void _disposePictures() {
    for (final p in _pictureCache.values) {
      p.dispose();
    }
    _pictureCache.clear();
  }

  /// 翻到下一页后重映射：old next → current, old current → previous
  void _shiftPicturesForward() {
    final prev = _pictureCache.remove(PageType.previous);
    final cur = _pictureCache.remove(PageType.current);
    final next = _pictureCache.remove(PageType.next);

    prev?.dispose();
    if (cur != null) _pictureCache[PageType.previous] = cur;
    if (next != null) _pictureCache[PageType.current] = next;
    // 新的 next 将在 _ensurePicture 时按需录制
  }

  /// 翻到上一页后重映射：old previous → current, old current → next
  void _shiftPicturesBackward() {
    final prev = _pictureCache.remove(PageType.previous);
    final cur = _pictureCache.remove(PageType.current);
    final next = _pictureCache.remove(PageType.next);

    next?.dispose();
    if (prev != null) _pictureCache[PageType.current] = prev;
    if (cur != null) _pictureCache[PageType.next] = cur;
    // 新的 previous 将在 _ensurePicture 时按需录制
  }

  /// 外部调用时同步清理滚动缓存
  @override
  void invalidateCache() {
    super.invalidateCache();
    _disposePictures();
    _pageOffset = 0;
  }

  // ==================== Tap 翻页 ====================

  @override
  void startTapAnim(PageDirection dir) {
    if (_status == _ScrollStatus.fling) {
      _stopFlingImmediate();
    }
    if (_status != _ScrollStatus.idle) return;
    if (dir == PageDirection.none) return;

    final type =
        dir == PageDirection.next ? PageType.next : PageType.previous;
    if (!callback.hasPage(type)) return;

    // 以固定速度触发 fling，模拟点击翻页
    final velocity =
        dir == PageDirection.next ? -viewHeight * 3.0 : viewHeight * 3.0;
    _startFling(velocity);
  }

  // ==================== 生命周期 ====================

  @override
  void dispose() {
    _disposePictures();
    super.dispose();
  }
}

/// 滚动状态
enum _ScrollStatus {
  idle, // 空闲
  press, // 按下
  drag, // 拖拽中
  fling, // 惯性滑动中
}
