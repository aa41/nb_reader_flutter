import 'package:flutter/material.dart';

import '../text/config/text_config.dart';
import '../text/engine/text_canvas.dart';
import '../text/engine/text_engine.dart';
import '../text/engine/text_model.dart';
import '../text/engine/text_page_controller.dart';
import '../text/entity/text_position.dart';
import 'anim/anim_page_painter.dart';
import 'anim/cover_page_animation.dart';
import 'anim/none_page_animation.dart';
import 'anim/page_animation.dart';
import 'anim/simulation_page_animation.dart';
import 'anim/scroll_page_animation.dart';
import 'anim/slide_page_animation.dart';
import 'page_enum.dart';

/// 页面变化回调
typedef OnPageChanged = void Function(
    PagePosition position, PageProgress progress);

/// 菜单区域点击回调
typedef OnMenuTap = void Function();

/// 文本阅读器 Widget
/// 集成 TextEngine + PageAnimation + GestureDetector
class TextReaderWidget extends StatefulWidget {
  final TextModel textModel;
  final TextConfig? textConfig;
  final PageAnimType animType;
  final OnPageChanged? onPageChanged;
  final OnMenuTap? onMenuTap;

  const TextReaderWidget({
    super.key,
    required this.textModel,
    this.textConfig,
    this.animType = PageAnimType.slide,
    this.onPageChanged,
    this.onMenuTap,
  });

  @override
  State<TextReaderWidget> createState() => TextReaderWidgetState();
}

class TextReaderWidgetState extends State<TextReaderWidget>
    with TickerProviderStateMixin
    implements PageAnimCallback {
  late TextEngine _engine;
  PageAnimation? _pageAnim;
  int _version = 0;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _engine = TextEngine(widget.textConfig ?? TextConfig());
    _createAnimation(widget.animType);
    // 当图片异步解码完成后，重新分页并重绘（图片实际尺寸可能与占位符不同）
    TextCanvas.onImageDecoded = () {
      if (mounted) {
        _engine.repaginate();
        _pageAnim?.invalidateCache();
        _invalidate();
      }
    };
  }

  @override
  void dispose() {
    TextCanvas.onImageDecoded = null;
    _pageAnim?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TextReaderWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.textConfig != widget.textConfig && widget.textConfig != null) {
      _engine.setTextConfig(widget.textConfig!);
      _pageAnim?.invalidateCache();
      _invalidate();
    }
    if (oldWidget.animType != widget.animType) {
      _switchAnimation(widget.animType);
    }
  }

  void _createAnimation(PageAnimType type) {
    _pageAnim = _buildAnimation(type);
    if (_isInitialized) {
      _pageAnim!.setViewPort(_engine.viewWidth, _engine.viewHeight);
    }
  }

  void _switchAnimation(PageAnimType type) {
    _pageAnim?.dispose();
    _createAnimation(type);
    _invalidate();
  }

  PageAnimation _buildAnimation(PageAnimType type) {
    return switch (type) {
      PageAnimType.none => NonePageAnimation(vsync: this, callback: this),
      PageAnimType.slide => SlidePageAnimation(vsync: this, callback: this),
      PageAnimType.cover => CoverPageAnimation(vsync: this, callback: this),
      PageAnimType.simulation =>
        SimulationPageAnimation(vsync: this, callback: this),
      PageAnimType.scroll =>
        ScrollPageAnimation(vsync: this, callback: this),
    };
  }

  void _initEngine(int width, int height) {
    if (width == 0 || height == 0) return;

    if (!_isInitialized) {
      _engine.setViewPort(width, height);
      _engine.init(widget.textModel);
      _isInitialized = true;
      _pageAnim?.setViewPort(width, height);
      _invalidate();
    } else if (_engine.viewWidth != width || _engine.viewHeight != height) {
      _engine.setViewPort(width, height);
      _pageAnim?.setViewPort(width, height);
      _invalidate();
    }
  }

  void _invalidate() {
    if (!mounted) return;
    setState(() => _version++);
    // 延迟通知, 避免在 build/didUpdateWidget 期间调用父级 setState
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _notifyPageChanged();
    });
  }

  void _notifyPageChanged() {
    if (widget.onPageChanged == null) return;
    final controller = _engine.pageController;
    if (controller == null) return;

    final pos = controller.getPagePosition(PageType.current);
    final progress = controller.getPageProgress(PageType.current);
    if (pos != null && progress != null) {
      widget.onPageChanged!(pos, progress);
    }
  }

  // === PageAnimCallback ===

  @override
  bool hasPage(PageType type) {
    return _engine.pageController?.hasPage(type) ?? false;
  }

  @override
  void turnPage(PageType type) {
    final controller = _engine.pageController;
    if (controller == null || !controller.hasPage(type)) return;
    controller.turnPage(type);
  }

  @override
  void drawPage(Canvas canvas, PageType type) {
    _engine.draw(canvas, type);
  }

  @override
  void invalidate() {
    _invalidate();
  }

  // === 对外 API ===

  /// 翻页(带动画)
  void turnPageAnimated(PageType type) {
    if (_pageAnim == null || !(_pageAnim!.isIdle)) return;
    final dir = type == PageType.next
        ? PageDirection.next
        : PageDirection.previous;
    _pageAnim!.startTapAnim(dir);
  }

  /// 翻页(直接, 无动画)
  void turnPageDirect(PageType type) {
    final controller = _engine.pageController;
    if (controller == null || !controller.hasPage(type)) return;
    controller.turnPage(type);
    _pageAnim?.invalidateCache();
    _invalidate();
  }

  /// 切换动画类型
  void setAnimType(PageAnimType type) {
    if (widget.animType == type) return;
    _switchAnimation(type);
  }

  /// 跳转章节
  void skipChapter(int chapterIndex) {
    final controller = _engine.pageController;
    if (controller == null) return;
    controller.skipPageByPagePosition(PagePosition(chapterIndex, 0));
    _pageAnim?.invalidateCache();
    _invalidate();
  }

  /// 跳转到指定位置（章节+页码），用于恢复阅读进度
  /// 注意：页码在配置变更后可能不准确，推荐使用 [skipToTextPosition]
  void skipToPosition(int chapterIndex, int pageIndex) {
    final controller = _engine.pageController;
    if (controller == null) return;
    controller.skipPageByPagePosition(PagePosition(chapterIndex, pageIndex));
    _pageAnim?.invalidateCache();
    _invalidate();
  }

  /// 跳转到精确文本位置（基于段落+元素+字符索引），用于恢复阅读进度
  /// 此方法在字号/行距/边距等配置变化后仍能准确恢复位置
  void skipToTextPosition(TextFixedPosition position) {
    final controller = _engine.pageController;
    if (controller == null) return;
    controller.skipPageByPosition(position);
    _pageAnim?.invalidateCache();
    _invalidate();
  }

  /// 获取当前精确文本位置（段落+元素+字符索引）
  /// 用于保存阅读进度，配合 [skipToTextPosition] 恢复
  TextFixedPosition? getTextPosition() {
    final page = _engine.pageController?.getCurrentPage();
    if (page == null) return null;
    return TextFixedPosition.fromPosition(page.startWordCursor);
  }

  /// 获取当前页码信息
  PageProgress? getProgress() {
    return _engine.pageController?.getPageProgress(PageType.current);
  }

  /// 获取当前位置
  PagePosition? getPosition() {
    return _engine.pageController?.getPagePosition(PageType.current);
  }

  /// 是否有下一页
  bool hasNextPage() {
    return _engine.pageController?.hasPage(PageType.next) ?? false;
  }

  /// 是否有上一页
  bool hasPrevPage() {
    return _engine.pageController?.hasPage(PageType.previous) ?? false;
  }

  /// 获取引擎实例（用于获取章节列表等信息）
  TextEngine get engine => _engine;

  /// 是否已初始化
  bool get isInitialized => _isInitialized;

  /// 更新 TextConfig（字号等配置变更）
  void updateTextConfig(TextConfig config) {
    _engine.setTextConfig(config);
    _pageAnim?.invalidateCache();
    _invalidate();
  }

  // === 手势处理 ===

  void _onTapUp(TapUpDetails details) {
    if (_pageAnim != null && !_pageAnim!.isIdle) return;

    final width = context.size?.width ?? 0;
    final x = details.localPosition.dx;

    if (x < width / 3) {
      turnPageAnimated(PageType.previous);
    } else if (x > width * 2 / 3) {
      turnPageAnimated(PageType.next);
    } else {
      widget.onMenuTap?.call();
    }
  }

  void _onPanStart(DragStartDetails details) {
    _pageAnim?.onPanStart(details);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    _pageAnim?.onPanUpdate(details);
  }

  void _onPanEnd(DragEndDetails details) {
    _pageAnim?.onPanEnd(details);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.toInt();
        final height = constraints.maxHeight.toInt();

        // 初始化/更新引擎视口
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _initEngine(width, height);
        });

        return GestureDetector(
          onTapUp: _onTapUp,
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          behavior: HitTestBehavior.opaque,
          child: _isInitialized && _pageAnim != null
              ? CustomPaint(
                  painter: AnimPagePainter(
                    animation: _pageAnim!,
                    version: _version,
                  ),
                  size: Size.infinite,
                )
              : Container(
                  color: Color(
                      widget.textConfig?.bgColor ?? TextConfig().bgColor),
                ),
        );
      },
    );
  }
}
