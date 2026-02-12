import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../page_enum.dart';
import 'page_animation.dart';

/// 仿真翻页动画 - 1:1 移植 Kotlin SimulationPageAnimation.kt
/// 使用贝塞尔曲线模拟纸张卷曲，包含:
/// - Householder 反射矩阵(翻起页背面)
/// - 翻起页前方阴影(vertical + horizontal)
/// - 下层页背面阴影(旋转渐变)
/// - 折叠阴影(旋转渐变)
class SimulationPageAnimation extends PageAnimation {
  // 页脚坐标
  int _cornerX = 1;
  int _cornerY = 1;

  // Bezier 曲线点
  double _bezierStart1X = 0, _bezierStart1Y = 0;
  double _bezierControl1X = 0, _bezierControl1Y = 0;
  double _bezierVertex1X = 0, _bezierVertex1Y = 0;
  double _bezierEnd1X = 0, _bezierEnd1Y = 0;

  double _bezierStart2X = 0, _bezierStart2Y = 0;
  double _bezierControl2X = 0, _bezierControl2Y = 0;
  double _bezierVertex2X = 0, _bezierVertex2Y = 0;
  double _bezierEnd2X = 0, _bezierEnd2Y = 0;

  double _middleX = 0;
  double _middleY = 0;
  double _degrees = 0; // 阴影旋转角度
  double _touchToCornerDis = 0;
  double _maxLength = 0;

  bool _isRTandLB = false; // 是否右上左下角

  // 浮点触摸坐标 (Simulation 需要浮点精度)
  double _floatTouchX = 0.01;
  double _floatTouchY = 0.01;
  double _startY = 0;

  SimulationPageAnimation({
    required super.vsync,
    required super.callback,
  });

  @override
  void setViewPort(int width, int height) {
    super.setViewPort(width, height);
    _maxLength = math.sqrt(width * width + height * height);
  }

  @override
  void onPanStart(DragStartDetails details) {
    super.onPanStart(details);
    _startY = details.localPosition.dy;
    _floatTouchX = details.localPosition.dx;
    _floatTouchY = details.localPosition.dy;
  }

  @override
  void onPanUpdate(DragUpdateDetails details) {
    if (status != AnimStatus.manual) return;
    lastX = touchX;
    touchX = details.localPosition.dx;
    _floatTouchX = details.localPosition.dx;

    // 首次移动确定方向
    if (direction == PageDirection.none) {
      final dx = touchX - startX;
      if (dx.abs() < 2) return;

      if (dx > 0) {
        // 向右拖 → 上一页
        direction = PageDirection.previous;
        if (!callback.hasPage(PageType.previous)) {
          _cancelDrag();
          return;
        }
        // 上一页: 从底部翻页, 根据起始X确定角落
        _calcCornerXY(startX > viewWidth / 2 ? startX.toInt() : (viewWidth - startX.toInt()), viewHeight);
        _floatTouchY = viewHeight.toDouble();
      } else {
        // 向左拖 → 下一页
        direction = PageDirection.next;
        if (!callback.hasPage(PageType.next)) {
          _cancelDrag();
          return;
        }
        // 下一页: 根据起始位置确定角落
        if (startX < viewWidth / 2) {
          _calcCornerXY(viewWidth - startX.toInt(), _startY.toInt());
        } else {
          _calcCornerXY(startX.toInt(), _startY.toInt());
        }
        // 限制 Y 坐标
        if (_startY > viewHeight / 3 && _startY < viewHeight / 2) {
          _floatTouchY = 1.0;
        } else if (_startY >= viewHeight / 2 && _startY < viewHeight * 2 / 3) {
          _floatTouchY = viewHeight.toDouble();
        } else {
          _floatTouchY = details.localPosition.dy.clamp(1.0, viewHeight - 1.0);
        }
      }
    } else {
      // 已有方向, 更新Y坐标
      if (direction == PageDirection.previous) {
        _floatTouchY = viewHeight.toDouble();
      } else {
        if (_startY > viewHeight / 3 && _startY < viewHeight / 2) {
          _floatTouchY = 1.0;
        } else if (_startY >= viewHeight / 2 && _startY < viewHeight * 2 / 3) {
          _floatTouchY = viewHeight.toDouble();
        } else {
          _floatTouchY = details.localPosition.dy.clamp(1.0, viewHeight - 1.0);
        }
      }
    }

    callback.invalidate();
  }

  void _cancelDrag() {
    status = AnimStatus.idle;
    direction = PageDirection.none;
    callback.invalidate();
  }

  void _calcCornerXY(int x, int y) {
    _cornerX = (x <= viewWidth / 2) ? 0 : viewWidth;
    _cornerY = (y <= viewHeight / 2) ? 0 : viewHeight;
    _isRTandLB = ((_cornerX == 0 && _cornerY == viewHeight) ||
        (_cornerX == viewWidth && _cornerY == 0));
  }

  @override
  void startTapAnim(PageDirection dir) {
    if (status != AnimStatus.idle) return;
    if (dir == PageDirection.none) return;

    final pageType = dir == PageDirection.next ? PageType.next : PageType.previous;
    if (!callback.hasPage(pageType)) return;

    direction = dir;

    if (dir == PageDirection.next) {
      // 下一页: touch从右下角附近开始, corner = 右下
      startX = viewWidth.toDouble();
      touchX = viewWidth - 1.0;
      _floatTouchX = viewWidth - 1.0;
      _floatTouchY = viewHeight - 1.0;
      _startY = viewHeight.toDouble();
      _calcCornerXY(viewWidth, viewHeight);
    } else {
      // 上一页: touch从左侧开始, corner 始终为右下
      startX = 0;
      touchX = 1.0;
      _floatTouchX = 1.0;
      _floatTouchY = viewHeight.toDouble();
      _startY = viewHeight.toDouble();
      _calcCornerXY(viewWidth, viewHeight);
    }

    _startAutoForward();
  }

  // 动画起始点保存
  double _animStartTouchX = 0;
  double _animStartTouchY = 0;
  double _animTargetTouchX = 0;
  double _animTargetTouchY = 0;

  void _startAutoForward() {
    status = AnimStatus.autoForward;

    _animStartTouchX = _floatTouchX;
    _animStartTouchY = _floatTouchY;

    // 计算目标点 (移植自 Kotlin startAnim - AutoForward)
    double dx, dy;
    if (_cornerX > 0 && direction == PageDirection.next) {
      // NEXT: touch向左移动超过屏幕
      dx = -(viewWidth + _floatTouchX);
    } else {
      // PREVIOUS: touch向右移动超过屏幕
      dx = viewWidth - _floatTouchX + viewWidth;
    }
    // 注意: AutoForward 不需要额外的 direction 检查(Kotlin原码中仅 Backward 有)

    dy = _cornerY > 0
        ? (viewHeight - _floatTouchY)
        : (1 - _floatTouchY);

    _animTargetTouchX = _floatTouchX + dx;
    _animTargetTouchY = _floatTouchY + dy;

    animController.duration = const Duration(milliseconds: 400);
    animController.forward(from: 0);
  }

  void _startAutoBackward() {
    status = AnimStatus.autoBackward;

    _animStartTouchX = _floatTouchX;
    _animStartTouchY = _floatTouchY;

    // 计算回退目标点 (移植自 Kotlin startAnim backward)
    double dx;
    if (_cornerX > 0 && direction == PageDirection.next) {
      dx = viewWidth - _floatTouchX;
    } else {
      dx = -_floatTouchX;
    }

    if (direction != PageDirection.next) {
      dx = -(viewWidth + _floatTouchX);
    }

    final dy = _cornerY > 0
        ? (viewHeight - _floatTouchY)
        : -_floatTouchY;

    _animTargetTouchX = _floatTouchX + dx;
    _animTargetTouchY = _floatTouchY + dy;

    animController.duration = const Duration(milliseconds: 300);
    animController.forward(from: 0);
  }

  @override
  void onPanEnd(DragEndDetails details) {
    if (status != AnimStatus.manual || direction == PageDirection.none) {
      _cancelDrag();
      return;
    }

    final dis = math.sqrt(
      math.pow(_floatTouchX - _cornerX, 2) +
          math.pow(_floatTouchY - _cornerY, 2),
    );
    final maxDis = math.sqrt(viewWidth * viewWidth + viewHeight * viewHeight);

    // 判断是否完成翻页: 距离超过 2/3 或速度足够
    final shouldComplete = dis < maxDis / 3 ||
        details.velocity.pixelsPerSecond.distance > 500;

    if (shouldComplete) {
      _startAutoForward();
    } else {
      _startAutoBackward();
    }
  }

  @override
  void onAnimUpdate() {
    if (status == AnimStatus.idle) return;

    final progress = animController.value;

    // 线性插值: 从起始点到目标点
    _floatTouchX = _animStartTouchX + (_animTargetTouchX - _animStartTouchX) * progress;
    _floatTouchY = _animStartTouchY + (_animTargetTouchY - _animStartTouchY) * progress;

    // 应用 Y 坐标钳制（对应 Kotlin mTouchY setter 逻辑）
    _applyTouchYClamping();

    touchX = _floatTouchX;
    callback.invalidate();
  }

  /// 应用触摸点 Y 坐标钳制
  /// Kotlin 原版中 mTouchY 的 setter 会在每次赋值时自动钳制 Y 坐标，
  /// 确保翻页动画时阴影与翻页曲线对齐。
  void _applyTouchYClamping() {
    // 条件 1: 起始点在中间三分之一区域 或 方向为上一页 → Y 强制到底部
    if (_startY > viewHeight / 3 && _startY < viewHeight * 2 / 3 ||
        direction == PageDirection.previous) {
      _floatTouchY = viewHeight.toDouble();
    }
    // 条件 2: 起始点在中间上半区域 且 方向为下一页 → Y 强制到顶部
    if (_startY > viewHeight / 3 && _startY < viewHeight / 2 &&
        direction == PageDirection.next) {
      _floatTouchY = 1.0;
    }
  }

  // ========== 贝塞尔曲线计算 ==========

  void _calcPoints() {
    _middleX = (_floatTouchX + _cornerX) / 2;
    _middleY = (_floatTouchY + _cornerY) / 2;

    final cxm = _cornerX - _middleX;
    final cym = _cornerY - _middleY;

    _bezierControl1X = cxm.abs() < 0.001
        ? _middleX
        : _middleX - cym * cym / cxm;
    _bezierControl1Y = _cornerY.toDouble();

    _bezierControl2X = _cornerX.toDouble();
    _bezierControl2Y = cym.abs() < 0.001
        ? _middleY - cxm * cxm / 0.1
        : _middleY - cxm * cxm / cym;

    _bezierStart1X = _bezierControl1X - (_cornerX - _bezierControl1X) / 2;
    _bezierStart1Y = _cornerY.toDouble();

    // === 边界修正 (Kotlin lines 582-616) ===
    if (_floatTouchX > 0 && _floatTouchX < viewWidth) {
      if (_bezierStart1X < 0 || _bezierStart1X > viewWidth) {
        if (_bezierStart1X < 0) {
          _bezierStart1X = viewWidth - _bezierStart1X;
        }

        final f1 = (_cornerX - _floatTouchX).abs();
        final f2 = viewWidth * f1 / _bezierStart1X;
        _floatTouchX = (_cornerX - f2).abs();

        final f3 = (_cornerX - _floatTouchX).abs() *
            (_cornerY - _floatTouchY).abs() / f1;
        _floatTouchY = (_cornerY - f3).abs();

        _middleX = (_floatTouchX + _cornerX) / 2;
        _middleY = (_floatTouchY + _cornerY) / 2;

        final cxm2 = _cornerX - _middleX;
        final cym2 = _cornerY - _middleY;

        _bezierControl1X = _middleX - cym2 * cym2 / cxm2;
        _bezierControl1Y = _cornerY.toDouble();

        _bezierControl2X = _cornerX.toDouble();
        _bezierControl2Y = cym2.abs() < 0.001
            ? _middleY - cxm2 * cxm2 / 0.1
            : _middleY - cxm2 * cxm2 / cym2;

        _bezierStart1X =
            _bezierControl1X - (_cornerX - _bezierControl1X) / 2;
      }
    }

    _bezierStart2X = _cornerX.toDouble();
    _bezierStart2Y = _bezierControl2Y - (_cornerY - _bezierControl2Y) / 2;

    _touchToCornerDis = math.sqrt(
      (_floatTouchX - _cornerX) * (_floatTouchX - _cornerX) +
          (_floatTouchY - _cornerY) * (_floatTouchY - _cornerY),
    );

    final end1 = _getCross(
      _floatTouchX, _floatTouchY,
      _bezierControl1X, _bezierControl1Y,
      _bezierStart1X, _bezierStart1Y,
      _bezierStart2X, _bezierStart2Y,
    );
    _bezierEnd1X = end1.dx;
    _bezierEnd1Y = end1.dy;

    final end2 = _getCross(
      _floatTouchX, _floatTouchY,
      _bezierControl2X, _bezierControl2Y,
      _bezierStart1X, _bezierStart1Y,
      _bezierStart2X, _bezierStart2Y,
    );
    _bezierEnd2X = end2.dx;
    _bezierEnd2Y = end2.dy;

    _bezierVertex1X =
        (_bezierStart1X + 2 * _bezierControl1X + _bezierEnd1X) / 4;
    _bezierVertex1Y =
        (2 * _bezierControl1Y + _bezierStart1Y + _bezierEnd1Y) / 4;
    _bezierVertex2X =
        (_bezierStart2X + 2 * _bezierControl2X + _bezierEnd2X) / 4;
    _bezierVertex2Y =
        (2 * _bezierControl2Y + _bezierStart2Y + _bezierEnd2Y) / 4;
  }

  /// 求解直线P1P2和直线P3P4的交点坐标
  Offset _getCross(
      double p1x, double p1y, double p2x, double p2y,
      double p3x, double p3y, double p4x, double p4y) {
    final a1 = (p2y - p1y) / (p2x - p1x);
    final b1 = (p1x * p2y - p2x * p1y) / (p1x - p2x);
    final a2 = (p4y - p3y) / (p4x - p3x);
    final b2 = (p3x * p4y - p4x * p3y) / (p3x - p4x);
    final x = (b2 - b1) / (a1 - a2);
    final y = a1 * x + b1;
    return Offset(x, y);
  }

  // ========== 绘制入口 ==========

  @override
  void drawMove(Canvas canvas, Size size) {
    _calcPoints();

    final fromPic = getFromPicture();
    final toPic = getToPicture();

    if (direction == PageDirection.previous) {
      _drawCurrentPageArea(canvas, toPic);
      _drawNextPageAreaAndShadow(canvas, fromPic);
    //  _drawCurrentPageShadow(canvas);
      _drawCurrentBackArea(canvas, toPic);
    } else if (direction == PageDirection.next) {
      _drawCurrentPageArea(canvas, fromPic);
      _drawNextPageAreaAndShadow(canvas, toPic);
  //    _drawCurrentPageShadow(canvas);
      _drawCurrentBackArea(canvas, fromPic);
    }
  }

  // ========== Path0: 翻页卷曲区域 ==========

  Path _buildPath0() {
    final path = Path();
    path.moveTo(_bezierStart1X, _bezierStart1Y);
    path.quadraticBezierTo(
        _bezierControl1X, _bezierControl1Y, _bezierEnd1X, _bezierEnd1Y);
    path.lineTo(_floatTouchX, _floatTouchY);
    path.lineTo(_bezierEnd2X, _bezierEnd2Y);
    path.quadraticBezierTo(
        _bezierControl2X, _bezierControl2Y, _bezierStart2X, _bezierStart2Y);
    path.lineTo(_cornerX.toDouble(), _cornerY.toDouble());
    path.close();
    return path;
  }

  Path _fullRectPath() {
    return Path()
      ..addRect(
          Rect.fromLTWH(0, 0, viewWidth.toDouble(), viewHeight.toDouble()));
  }

  /// 围绕(px,py)旋转canvas
  void _rotateCanvas(Canvas canvas, double degrees, double px, double py) {
    canvas.translate(px, py);
    canvas.rotate(degrees * math.pi / 180);
    canvas.translate(-px, -py);
  }

  // ========== 1. 绘制当前页(翻页区域外) ==========

  void _drawCurrentPageArea(Canvas canvas, ui.Picture? pic) {
    if (pic == null) return;
    final path0 = _buildPath0();
    canvas.save();
    // XOR: 绘制 path0 之外的区域
    canvas.clipPath(Path.combine(PathOperation.difference, _fullRectPath(), path0));
    canvas.drawPicture(pic);
    canvas.restore();
  }

  // ========== 2. 绘制下层页 + 背面阴影 ==========

  void _drawNextPageAreaAndShadow(Canvas canvas, ui.Picture? pic) {
    if (pic == null) return;

    final path1 = Path()
      ..moveTo(_bezierStart1X, _bezierStart1Y)
      ..lineTo(_bezierVertex1X, _bezierVertex1Y)
      ..lineTo(_bezierVertex2X, _bezierVertex2Y)
      ..lineTo(_bezierStart2X, _bezierStart2Y)
      ..lineTo(_cornerX.toDouble(), _cornerY.toDouble())
      ..close();

    // 计算阴影旋转角度
    _degrees = math.atan2(
          _bezierControl1X - _cornerX,
          _bezierControl2Y - _cornerY,
        ) *
        180 /
        math.pi;

    final path0 = _buildPath0();

    canvas.save();
    canvas.clipPath(path0);
    canvas.clipPath(path1);
    canvas.drawPicture(pic);

    // 绘制背面阴影(旋转渐变)
    final int leftX, rightX;
    final List<Color> colors;
    if (_isRTandLB) {
      leftX = _bezierStart1X.toInt();
      rightX = (_bezierStart1X + _touchToCornerDis / 4).toInt();
      colors = const [Color(0xFF111111), Color(0x00111111)];
    } else {
      leftX = (_bezierStart1X - _touchToCornerDis / 4).toInt();
      rightX = _bezierStart1X.toInt();
      colors = const [Color(0x00111111), Color(0xFF111111)];
    }

    _rotateCanvas(canvas, _degrees, _bezierStart1X, _bezierStart1Y);
    final shadowRect = Rect.fromLTRB(
      leftX.toDouble(),
      _bezierStart1Y,
      rightX.toDouble(),
      _maxLength + _bezierStart1Y,
    );
    final shadowPaint = Paint()
      ..shader = ui.Gradient.linear(
        shadowRect.centerLeft,
        shadowRect.centerRight,
        colors,
      );
    canvas.drawRect(shadowRect, shadowPaint);
    canvas.restore();
  }

  // ========== 3. 绘制翻起页前方阴影 ==========

  // ignore: unused_element
  void _drawCurrentPageShadow(Canvas canvas) {
    final double degree;
    if (_isRTandLB) {
      degree = math.pi / 4 -
          math.atan2(_bezierControl1Y - _floatTouchY,
              _floatTouchX - _bezierControl1X);
    } else {
      degree = math.pi / 4 -
          math.atan2(_floatTouchY - _bezierControl1Y,
              _floatTouchX - _bezierControl1X);
    }
    final d1 = 25.0 * 1.414 * math.cos(degree);
    final d2 = 25.0 * 1.414 * math.sin(degree);
    final x = _floatTouchX + d1;
    final y = _isRTandLB
        ? _floatTouchY + d2
        : _floatTouchY - d2;

    final path0 = _buildPath0();
    final h = viewHeight.toDouble();

    // ---- Section 1: 垂直阴影 (沿 bezierControl1 边) ----
    {
      final path1 = Path()
        ..moveTo(x, y)
        ..lineTo(_floatTouchX, _floatTouchY)
        ..lineTo(_bezierControl1X, _bezierControl1Y)
        ..lineTo(_bezierStart1X, _bezierStart1Y)
        ..close();

      canvas.save();
      // XOR clip: outside path0
      canvas.clipPath(
          Path.combine(PathOperation.difference, _fullRectPath(), path0));
      canvas.clipPath(path1);

      final int leftX, rightX;
      final List<Color> colors;
      if (_isRTandLB) {
        leftX = _bezierControl1X.toInt();
        rightX = _bezierControl1X.toInt() + 25;
        colors = const [Color(0x80111111), Color(0x00111111)];
      } else {
        leftX = (_bezierControl1X - 25).toInt();
        rightX = _bezierControl1X.toInt() + 1;
        colors = const [Color(0x00111111), Color(0x80111111)];
      }

      final rotateDeg = math.atan2(
            _floatTouchX - _bezierControl1X,
            _bezierControl1Y - _floatTouchY,
          ) *
          180 /
          math.pi;
      _rotateCanvas(canvas, rotateDeg, _bezierControl1X, _bezierControl1Y);

      final rect = Rect.fromLTRB(
        leftX.toDouble(),
        _bezierControl1Y - _maxLength,
        rightX.toDouble(),
        _bezierControl1Y,
      );
      final paint = Paint()
        ..shader = ui.Gradient.linear(
          rect.centerLeft,
          rect.centerRight,
          colors,
        );
      canvas.drawRect(rect, paint);
      canvas.restore();
    }

    // ---- Section 2: 水平阴影 (沿 bezierControl2 边) ----
    {
      final path1 = Path()
        ..moveTo(x, y)
        ..lineTo(_floatTouchX, _floatTouchY)
        ..lineTo(_bezierControl2X, _bezierControl2Y)
        ..lineTo(_bezierStart2X, _bezierStart2Y)
        ..close();

      canvas.save();
      // XOR clip: outside path0
      canvas.clipPath(
          Path.combine(PathOperation.difference, _fullRectPath(), path0));
      canvas.clipPath(path1);

      final int topY, bottomY;
      final List<Color> colors;
      if (_isRTandLB) {
        topY = _bezierControl2Y.toInt();
        bottomY = (_bezierControl2Y + 25).toInt();
        colors = const [Color(0x80111111), Color(0x00111111)];
      } else {
        topY = (_bezierControl2Y - 25).toInt();
        bottomY = (_bezierControl2Y + 1).toInt();
        colors = const [Color(0x00111111), Color(0x80111111)];
      }

      final rotateDeg = math.atan2(
            _bezierControl2Y - _floatTouchY,
            _bezierControl2X - _floatTouchX,
          ) *
          180 /
          math.pi;
      _rotateCanvas(canvas, rotateDeg, _bezierControl2X, _bezierControl2Y);

      final temp = _bezierControl2Y < 0
          ? _bezierControl2Y - h
          : _bezierControl2Y;
      final hmg =
          math.sqrt(_bezierControl2X * _bezierControl2X + temp * temp)
              .toInt();

      final Rect rect;
      if (hmg > _maxLength) {
        rect = Rect.fromLTRB(
          _bezierControl2X - 25 - hmg,
          topY.toDouble(),
          _bezierControl2X + _maxLength - hmg,
          bottomY.toDouble(),
        );
      } else {
        rect = Rect.fromLTRB(
          _bezierControl2X - _maxLength,
          topY.toDouble(),
          _bezierControl2X,
          bottomY.toDouble(),
        );
      }
      final paint = Paint()
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          colors,
        );
      canvas.drawRect(rect, paint);
      canvas.restore();
    }
  }

  // ========== 4. 绘制翻起页背面(矩阵反射 + 折叠阴影) ==========

  void _drawCurrentBackArea(Canvas canvas, ui.Picture? pic) {
    // 折叠阴影宽度计算
    final i = ((_bezierStart1X + _bezierControl1X) / 2).toInt();
    final f1 = (i - _bezierControl1X).abs();
    final i1 = ((_bezierStart2Y + _bezierControl2Y) / 2).toInt();
    final f2 = (i1 - _bezierControl2Y).abs();
    final f3 = math.min(f1, f2);

    // 背面三角区域
    final path1 = Path()
      ..moveTo(_bezierVertex2X, _bezierVertex2Y)
      ..lineTo(_bezierVertex1X, _bezierVertex1Y)
      ..lineTo(_bezierEnd1X, _bezierEnd1Y)
      ..lineTo(_floatTouchX, _floatTouchY)
      ..lineTo(_bezierEnd2X, _bezierEnd2Y)
      ..close();

    final path0 = _buildPath0();

    canvas.save();
    canvas.clipPath(path0);
    canvas.clipPath(path1);

    // --- Householder 反射矩阵: 镜像页面内容到背面 ---
    if (pic != null) {
      final dis = math.sqrt(
        (_cornerX - _bezierControl1X) * (_cornerX - _bezierControl1X) +
            (_bezierControl2Y - _cornerY) * (_bezierControl2Y - _cornerY),
      );
      if (dis > 0.001) {
        final f8 = (_cornerX - _bezierControl1X) / dis;
        final f9 = (_bezierControl2Y - _cornerY) / dis;

        // 构造 4x4 列优先矩阵
        // Kotlin 3x3: [1-2*f9*f9, 2*f8*f9, 0; 2*f8*f9, 1-2*f8*f8, 0; 0,0,1]
        // Pre-translate(-cx,-cy), Post-translate(cx,cy)
        final cx = _bezierControl1X;
        final cy = _bezierControl1Y;

        final r00 = 1 - 2 * f9 * f9;
        final r01 = 2 * f8 * f9;
        final r10 = r01;
        final r11 = 1 - 2 * f8 * f8;

        // Result = PostTranslate * Reflection * PreTranslate
        // 直接构造合并后的 4x4 矩阵(列优先)
        final m = Float64List(16);
        m[0] = r00;
        m[1] = r10;
        m[4] = r01;
        m[5] = r11;
        m[10] = 1;
        m[15] = 1;
        // translation: post * (reflection * (-cx,-cy)) + (cx,cy)
        m[12] = cx - r00 * cx - r01 * cy;
        m[13] = cy - r10 * cx - r11 * cy;

        canvas.save();
        canvas.transform(m);
        canvas.drawPicture(pic);
        canvas.restore();
      }
    }

    // --- 折叠阴影(旋转渐变) ---
    final int left, right;
    final List<Color> folderColors;
    if (_isRTandLB) {
      left = (_bezierStart1X - 1).toInt();
      right = (_bezierStart1X + f3 + 1).toInt();
      folderColors = const [Color(0x00333333), Color(0xB0333333)];
    } else {
      left = (_bezierStart1X - f3 - 1).toInt();
      right = (_bezierStart1X + 1).toInt();
      folderColors = const [Color(0xB0333333), Color(0x00333333)];
    }

    _rotateCanvas(canvas, _degrees, _bezierStart1X, _bezierStart1Y);
    final folderRect = Rect.fromLTRB(
      left.toDouble(),
      _bezierStart1Y,
      right.toDouble(),
      _bezierStart1Y + _maxLength,
    );
    final folderPaint = Paint()
      ..shader = ui.Gradient.linear(
        folderRect.centerLeft,
        folderRect.centerRight,
        folderColors,
      );
    canvas.drawRect(folderRect, folderPaint);

    canvas.restore();
  }
}
