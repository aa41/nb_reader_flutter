import 'dart:math';
import 'dart:ui';

import '../config/text_config.dart';
import '../element/text_control_element.dart';
import '../element/text_element.dart';
import '../element/text_fixed_hspace_element.dart';
import '../element/text_image_element.dart';
import '../element/text_style_element.dart';
import '../element/text_word_element.dart';
import '../entity/text_metrics.dart';
import '../style/tree_text_style.dart';
import 'cursor/text_paragraph_cursor.dart';
import 'text_paint_context.dart';

/// 基础文本渲染引擎 - 管理样式栈和元素度量
/// 移植自 Kotlin BaseTextEngine
abstract class BaseTextEngine {
  /// 视口宽高
  int viewWidth = 0;
  int viewHeight = 0;

  /// 文本画笔上下文
  final TextPaintContext paintContext = TextPaintContext();

  /// 文本配置
  TextConfig _textConfig;

  /// 当前文本样式
  TreeTextStyle? _textStyle;

  /// 缓存
  int? _wordHeight;
  TextMetrics? _metrics;

  BaseTextEngine(this._textConfig);

  /// 子类实现
  void onSizeChanged(int width, int height);

  /// 设置视口
  void setViewPort(int width, int height) {
    viewWidth = width;
    viewHeight = height;
    _metrics = null;
    onSizeChanged(width, height);
  }

  /// 获取文本区域宽
  int getTextAreaWidth() =>
      viewWidth - _textConfig.getMarginLeft() - _textConfig.getMarginRight();

  /// 获取文本区域高
  int getTextAreaHeight() =>
      viewHeight - _textConfig.getMarginTop() - _textConfig.getMarginBottom();

  /// 获取文本区域尺寸
  Size getTextAreaSize() =>
      Size(getTextAreaWidth().toDouble(), getTextAreaHeight().toDouble());

  TextConfig getTextConfig() => _textConfig;

  void setTextConfig(TextConfig config) {
    _textConfig = config;
    _metrics = null;
    _wordHeight = null;
    _textStyle = null;
  }

  // === 样式管理 ===

  /// 设置当前文本样式
  void setTextStyle(TreeTextStyle style) {
    if (_textStyle != style) {
      _textStyle = style;
      _wordHeight = null;
    }

    paintContext.setFont(
      fontSize: style.getFontSize(getMetrics()).toDouble(),
      bold: style.isBold(),
      italic: style.isItalic(),
      underline: style.isUnderline(),
      strikeThrough: style.isStrikeThrough(),
      fontFamily: style.getFontFamily(),
      letterSpacing: style.getLetterSpacing(),
    );
  }

  /// 获取当前文本样式
  TreeTextStyle getTextStyle() {
    _textStyle ??= _textConfig.getBaseTextStyle();
    return _textStyle!;
  }

  /// 重置文本样式
  void resetTextStyle() {
    setTextStyle(_textConfig.getBaseTextStyle());
  }

  /// 判断是否是样式元素
  bool isStyleElement(TextElement element) {
    return identical(element, TextElement.styleClose) ||
        element is TextStyleElement ||
        element is TextControlElement;
  }

  /// 应用样式元素
  void applyStyleElement(TextElement element) {
    if (identical(element, TextElement.styleClose)) {
      _applyStyleClose();
    } else if (element is TextStyleElement) {
      _applyStyle(element);
    } else if (element is TextControlElement) {
      _applyControl(element);
    }
  }

  /// 应用从 cursor 的 index 到 end 之间的样式
  void applyStyleChange(TextParagraphCursor cursor, int index, int end) {
    for (var i = index; i < end; i++) {
      final elem = cursor.getElement(i);
      if (elem != null && isStyleElement(elem)) {
        applyStyleElement(elem);
      }
    }
  }

  void _applyStyleClose() {
    final parent = _textStyle?.parent;
    if (parent != null) {
      setTextStyle(parent);
    }
  }

  void _applyStyle(TextStyleElement element) {
    setTextStyle(
      _textConfig.getCSSDecoratedStyle(_textStyle ?? getTextStyle(), element.styleTag),
    );
  }

  void _applyControl(TextControlElement control) {
    if (control.isStart) {
      setTextStyle(
        _textConfig.getControlDecoratedStyle(_textStyle ?? getTextStyle(), control.type),
      );
    } else {
      final parent = _textStyle?.parent;
      if (parent != null) {
        setTextStyle(parent);
      }
    }
  }

  // === 度量 ===

  TextMetrics getMetrics() {
    _metrics ??= TextMetrics(
      dpi: 160, // 默认 DPI
      screenWidth: viewWidth,
      screenHeight: viewHeight,
      baseFontSize: _textConfig.getBaseTextStyle().getFontSize(),
    );
    return _metrics!;
  }

  /// 计算元素宽度
  int getElementWidth(TextElement element, int charIndex) {
    if (element is TextWordElement) {
      return getWordWidth(element, charIndex);
    } else if (identical(element, TextElement.nbSpace)) {
      return paintContext.getSpaceWidth();
    } else if (identical(element, TextElement.indent)) {
      return getTextStyle().getFirstLineIndent(getMetrics());
    } else if (element is TextImageElement) {
      final size = paintContext.getImageSize(element.image, getTextAreaSize());
      return size?.width.toInt() ?? 0;
    }
    return 0;
  }

  /// 计算元素高度
  int getElementHeight(TextElement element) {
    if (identical(element, TextElement.nbSpace) ||
        element is TextWordElement ||
        element is TextFixedHSpaceElement) {
      return getWordHeight();
    } else if (element is TextImageElement) {
      final size = paintContext.getImageSize(element.image, getTextAreaSize());
      final imgH = size?.height.toInt() ?? 0;
      final lineExtra = (paintContext.getStringHeight() *
              (getTextStyle().getLineSpacePercent() - 100) / 100)
          .toInt();
      return imgH + max(lineExtra, 3);
    }
    return 0;
  }

  /// 计算元素 descent
  int getElementDescent(TextElement element) {
    if (element is TextWordElement) return paintContext.getDescent();
    return 0;
  }

  /// 计算单词宽度
  int getWordWidth(TextWordElement word, int start) {
    if (start == 0) {
      return word.getWidth(paintContext);
    }
    return paintContext.getStringWidth(
        word.data, word.offset + start, word.length - start);
  }

  /// 计算单词高度
  int getWordHeight() {
    if (_wordHeight != null) return _wordHeight!;
    final style = getTextStyle();
    _wordHeight = paintContext.getStringHeight() * style.getLineSpacePercent() ~/ 100 +
        style.getVerticalAlign(getMetrics());
    return _wordHeight!;
  }
}
