import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../config/text_config.dart';
import '../element/text_control_element.dart';
import '../element/text_element.dart';
import '../element/text_image_element.dart';
import '../element/text_word_element.dart';
import '../entity/text_element_area.dart';
import '../entity/text_line.dart';
import '../entity/text_page.dart';
import '../style/text_alignment_type.dart';
import 'base_text_engine.dart';
import 'cursor/text_paragraph_cursor.dart';
import 'cursor/text_word_cursor.dart';
import 'text_canvas.dart';
import 'text_model.dart';
import 'text_page_controller.dart';
import '../../widget/page_enum.dart';
import '../entity/text_position.dart';

/// 文本排版引擎
/// 移植自 Kotlin TextEngine
class TextEngine extends BaseTextEngine {
  TextModel? _textModel;
  TextPageController? _textPageController;

  TextEngine(super.textConfig);

  @override
  void setTextConfig(TextConfig config) {
    super.setTextConfig(config);
    // 清除模型缓存（TextWordElement 的宽度缓存依赖旧字体参数）
    _textModel?.clearCache();
    // 重新分页
    _initTextPageController(viewWidth, viewHeight);
  }

  /// 重新分页（不清除模型缓存，保留已解码的图片等数据）
  void repaginate() {
    _initTextPageController(viewWidth, viewHeight);
  }

  /// 初始化引擎
  void init(TextModel model) {
    _textModel = model;
    _initTextPageController(viewWidth, viewHeight);
  }

  void _initTextPageController(int width, int height) {
    if (_textModel == null || width == 0 || height == 0) return;

    final textAreaW = getTextAreaWidth();
    final textAreaH = getTextAreaHeight();
    if (textAreaW <= 0 || textAreaH <= 0) return;

    // 保存当前阅读位置（如果已有控制器）
    // 使用 TextFixedPosition（段落+元素+字符级定位），而非 PagePosition（页码），
    // 因为字号/行距/边距变化会导致分页改变，页码不再准确。
    TextFixedPosition? savedTextPos;
    if (_textPageController != null) {
      final curPage = _textPageController!.getCurrentPage();
      if (curPage != null) {
        savedTextPos = TextFixedPosition.fromPosition(curPage.startWordCursor);
      }
    }

    _textPageController = TextPageController(
      _textModel!,
      findPageEndCursor,
    );
    // 使用文本区域尺寸（扣除 margin），使分页计算与渲染一致
    _textPageController!.setViewPort(textAreaW, textAreaH);

    if (savedTextPos != null) {
      // 恢复阅读位置（基于文本光标，精确到段落+元素+字符）
      _textPageController!.skipPageByPosition(savedTextPos);
    } else if (_textModel!.getChapterCount() > 0) {
      _textPageController!.skipPageByPosition(
        _textModel!.getChapterCursor(0).getParagraphCursor(0),
      );
    }
  }

  @override
  void onSizeChanged(int width, int height) {
    _initTextPageController(width, height);
  }

  TextPageController? get pageController => _textPageController;

  // === 分页核心算法 ===

  /// 查找页面结尾光标
  /// 从 startWordCursor 开始，逐行布局直到填满页面高度
  TextWordCursor findPageEndCursor(
      int width, int height, TextWordCursor startWordCursor) {
    final findCursor = TextWordCursor.copy(startWordCursor);
    TextLine? curLine;
    bool hasNextParagraph;
    int remainAreaHeight = height;

    do {
      resetTextStyle();
      final preLine = curLine;
      final paragraphCursor = findCursor.getParagraphCursor();
      final curElementIndex = findCursor.elementIndex;
      final endElementIndex = paragraphCursor.getElementCount();

      // 应用当前位置之前的样式
      applyStyleChange(paragraphCursor, 0, curElementIndex);

      curLine = TextLine(paragraphCursor, curElementIndex,
          findCursor.charIndex, getTextStyle());

      while (curLine!.endElementIndex < endElementIndex) {
        curLine = prepareTextLine(
          width, paragraphCursor,
          curLine.endElementIndex, curLine.endCharIndex,
          endElementIndex, preLine,
        );

        remainAreaHeight -= (curLine.height + curLine.descent);
        if (remainAreaHeight <= 0) break;
        remainAreaHeight -= curLine.vSpaceAfter;

        findCursor.moveTo(curLine.endElementIndex, curLine.endCharIndex);
      }

      hasNextParagraph = findCursor.isEndOfParagraph() &&
          !findCursor.getParagraphCursor().isLastOfChapter() &&
          findCursor.moveToNextParagraph();
    } while (remainAreaHeight > 0 &&
        hasNextParagraph &&
        !findCursor.getParagraphCursor().isEndOfSection());

    resetTextStyle();
    return findCursor;
  }

  /// 准备页面（生成 TextLine 列表）
  void preparePage(TextPage page) {
    if (page.isPrepare) return;

    final pageStartCursor = page.startWordCursor;
    final pageEndCursor = page.endWordCursor;
    final findCursor = TextWordCursor.copy(pageStartCursor);
    final textLines = page.textLineList;
    TextLine? curLine;

    while (findCursor.compareToIgnoreChar(pageEndCursor) < 0) {
      resetTextStyle();
      final preLine = curLine;
      final paragraphCursor = findCursor.getParagraphCursor();
      final curElementIndex = findCursor.elementIndex;

      final endElementIndex =
          (identical(paragraphCursor, pageEndCursor.getParagraphCursor()) ||
                  paragraphCursor.paragraphIndex ==
                      pageEndCursor.paragraphIndex &&
                  paragraphCursor.chapterIndex ==
                      pageEndCursor.chapterIndex)
              ? pageEndCursor.elementIndex
              : paragraphCursor.getElementCount();

      applyStyleChange(paragraphCursor, 0, curElementIndex);

      curLine = TextLine(paragraphCursor, curElementIndex,
          findCursor.charIndex, getTextStyle());

      while (curLine!.endElementIndex < endElementIndex) {
        curLine = prepareTextLine(
          getTextAreaWidth(), paragraphCursor,
          curLine.endElementIndex, curLine.endCharIndex,
          endElementIndex, preLine,
        );

        findCursor.moveTo(curLine.endElementIndex, curLine.endCharIndex);
        textLines.add(curLine);
      }

      findCursor.moveToNextParagraph();
    }

    resetTextStyle();
    page.isPrepare = true;
  }

  /// 核心行布局算法
  TextLine prepareTextLine(
    int lineWidth,
    TextParagraphCursor paragraphCursor,
    int startElementIndex,
    int startCharIndex,
    int endElementIndex,
    TextLine? preLine,
  ) {
    final curLineInfo = TextLine(
        paragraphCursor, startElementIndex, startCharIndex, getTextStyle());

    var curElementIndex = startElementIndex;
    var curCharIndex = startCharIndex;
    final isFirstLine = startElementIndex == 0 && startCharIndex == 0;

    // 处理行首样式元素
    if (isFirstLine) {
      var element = paragraphCursor.getElement(curElementIndex);
      if (element != null) {
        while (isStyleElement(element!)) {
          applyStyleElement(element);
          ++curElementIndex;
          curCharIndex = 0;
          if (curElementIndex >= endElementIndex) break;
          element = paragraphCursor.getElement(curElementIndex)!;
        }
      }
      curLineInfo.startStyle = getTextStyle();
      curLineInfo.realStartElementIndex = curElementIndex;
      curLineInfo.realStartCharIndex = curCharIndex;
    }

    var curTextStyle = getTextStyle();
    final maxWidth = lineWidth - curTextStyle.getRightIndent(getMetrics());
    curLineInfo.leftIndent = curTextStyle.getLeftIndent(getMetrics());

    if (isFirstLine && curTextStyle.getAlignment() != TextAlignmentType.alignCenter) {
      curLineInfo.leftIndent += curTextStyle.getFirstLineIndent(getMetrics());
    }

    if (curLineInfo.leftIndent > maxWidth - 20) {
      curLineInfo.leftIndent = maxWidth * 3 ~/ 4;
    }

    curLineInfo.width = curLineInfo.leftIndent;

    if (curLineInfo.realStartElementIndex == endElementIndex) {
      curLineInfo.endElementIndex = curLineInfo.realStartElementIndex;
      curLineInfo.endCharIndex = curLineInfo.realStartCharIndex;
      return curLineInfo;
    }

    var newWidth = curLineInfo.width;
    var newHeight = curLineInfo.height;
    var newDescent = curLineInfo.descent;
    var wordOccurred = false;
    var isVisible = false;
    var lastSpaceWidth = 0;
    var internalSpaceCount = 0;
    var removeLastSpace = false;
    // 记录样式关闭前的最大 spaceAfter（用于段落结束时的间距计算）
    var maxSpaceAfterBeforeClose = 0;

    while (curElementIndex < endElementIndex) {
      final element = paragraphCursor.getElement(curElementIndex)!;
      newWidth += getElementWidth(element, curCharIndex);
      newHeight = max(newHeight, getElementHeight(element));
      newDescent = max(newDescent, getElementDescent(element));

      if (identical(element, TextElement.hSpace)) {
        if (wordOccurred) {
          wordOccurred = false;
          internalSpaceCount++;
          lastSpaceWidth = paintContext.getSpaceWidth();
          newWidth += lastSpaceWidth;
        }
      } else if (identical(element, TextElement.nbSpace)) {
        wordOccurred = true;
      } else if (element is TextWordElement) {
        wordOccurred = true;
        isVisible = true;
      } else if (element is TextImageElement) {
        wordOccurred = true;
        isVisible = true;
      } else if (isStyleElement(element)) {
        // 在应用样式关闭标签之前，保存当前样式的 spaceAfter
        // 避免样式弹出后丢失段后间距信息
        if (element is TextControlElement && !element.isStart) {
          final curSpaceAfter = getTextStyle().getSpaceAfter(getMetrics());
          if (curSpaceAfter > maxSpaceAfterBeforeClose) {
            maxSpaceAfterBeforeClose = curSpaceAfter;
          }
        }
        applyStyleElement(element);
      }

      // 超宽检测
      if (newWidth > maxWidth &&
          (curLineInfo.endElementIndex != startElementIndex ||
              element is TextWordElement)) {
        break;
      }

      ++curElementIndex;
      curCharIndex = 0;
      final previousElement = element;

      var allowBreak = curElementIndex >= endElementIndex;
      if (!allowBreak) {
        final nextElement = paragraphCursor.getElement(curElementIndex)!;
        allowBreak = !identical(previousElement, TextElement.nbSpace) &&
            !identical(nextElement, TextElement.nbSpace) &&
            (nextElement is! TextWordElement || previousElement is TextWordElement) &&
            nextElement is! TextImageElement &&
            nextElement is! TextControlElement;
      }

      if (allowBreak) {
        curLineInfo.isVisible = isVisible;
        curLineInfo.width = newWidth;
        if (curLineInfo.height < newHeight) curLineInfo.height = newHeight;
        if (curLineInfo.descent < newDescent) curLineInfo.descent = newDescent;
        curLineInfo.endElementIndex = curElementIndex;
        curLineInfo.endCharIndex = curCharIndex;
        curLineInfo.spaceCount = internalSpaceCount;
        curTextStyle = getTextStyle();
        removeLastSpace = !wordOccurred && internalSpaceCount > 0;
      }
    }

    // 跳过 hyphenation（简化）

    if (removeLastSpace) {
      curLineInfo.width -= lastSpaceWidth;
      curLineInfo.spaceCount--;
    }

    setTextStyle(curTextStyle);

    // 段前间距
    if (isFirstLine) {
      curLineInfo.vSpaceBefore = curLineInfo.startStyle.getSpaceBefore(getMetrics());
      if (preLine != null) {
        curLineInfo.previousInfoUsed = true;
        curLineInfo.height += max(0, curLineInfo.vSpaceBefore - preLine.vSpaceAfter);
      } else {
        curLineInfo.previousInfoUsed = false;
        curLineInfo.height += curLineInfo.vSpaceBefore;
      }
    }

    // 段后间距（取当前样式与关闭前样式的最大值）
    if (curLineInfo.isEndOfParagraph()) {
      final curSpaceAfter = getTextStyle().getSpaceAfter(getMetrics());
      curLineInfo.vSpaceAfter = curSpaceAfter > maxSpaceAfterBeforeClose
          ? curSpaceAfter
          : maxSpaceAfterBeforeClose;
    }

    // 防止死循环
    if (curLineInfo.endElementIndex == startElementIndex &&
        curLineInfo.endCharIndex == startCharIndex) {
      curLineInfo.endElementIndex = paragraphCursor.getElementCount();
      curLineInfo.endCharIndex = 0;
    }

    return curLineInfo;
  }

  /// 准备文本绘制区域
  List<int> prepareTextArea(TextPage page) {
    page.textElementAreaVector.clear();
    var y = 0;
    TextLine? previous;
    final labels = List<int>.filled(page.textLineList.length + 1, 0);

    for (int i = 0; i < page.textLineList.length; i++) {
      final lineInfo = page.textLineList[i];
      lineInfo.adjust(previous);
      lineInfo.y = y;
      _prepareTextAreaLine(page, lineInfo, 0, y);
      y += lineInfo.height + lineInfo.descent + lineInfo.vSpaceAfter;
      labels[i + 1] = page.textElementAreaVector.size();
      previous = lineInfo;
    }
    return labels;
  }

  void _prepareTextAreaLine(TextPage page, TextLine line, int x, int y) {
    var realX = x;
    var realY = min(y + line.height,
        getTextConfig().getMarginTop() + getTextAreaHeight() - 1);

    final paragraphCursor = line.paragraphCursor;
    setTextStyle(line.startStyle);
    var spaceCount = line.spaceCount;
    var fullCorrection = 0;
    final isEndOfParagraph = line.isEndOfParagraph();
    var isWordOccurred = false;
    var isStyleChange = true;

    realX += line.leftIndent;

    final maxWidth = getTextAreaWidth();

    switch (getTextStyle().getAlignment()) {
      case TextAlignmentType.alignRight:
        realX += maxWidth - getTextStyle().getRightIndent(getMetrics()) - line.width;
        break;
      case TextAlignmentType.alignCenter:
        realX += (maxWidth - getTextStyle().getRightIndent(getMetrics()) - line.width) ~/ 2;
        break;
      case TextAlignmentType.alignJustify:
        if (!isEndOfParagraph &&
            paragraphCursor.getElement(line.endElementIndex) != TextElement.afterParagraph) {
          fullCorrection = maxWidth - getTextStyle().getRightIndent(getMetrics()) - line.width;
        }
        break;
    }

    final chapterIdx = paragraphCursor.chapterIndex;
    final paragraphIdx = paragraphCursor.paragraphIndex;
    final endElementIndex = line.endElementIndex;
    var charIndex = line.realStartCharIndex;

    for (var wordIndex = line.realStartElementIndex;
        wordIndex < endElementIndex;
        wordIndex++) {
      final element = paragraphCursor.getElement(wordIndex);
      if (element == null) continue;
      final width = getElementWidth(element, charIndex);

      if (identical(element, TextElement.hSpace)) {
        if (isWordOccurred && spaceCount > 0) {
          final correction = fullCorrection ~/ spaceCount;
          final spaceLength = paintContext.getSpaceWidth() + correction;
          realX += spaceLength;
          fullCorrection -= correction;
          isWordOccurred = false;
          --spaceCount;
        }
      } else if (element is TextWordElement || element is TextImageElement) {
        final height = getElementHeight(element);
        final descent = getElementDescent(element);
        final length = element is TextWordElement ? element.length : 0;

        page.textElementAreaVector.add(TextElementArea(
          chapterIndex: chapterIdx,
          paragraphIndex: paragraphIdx,
          elementIndex: wordIndex,
          charIndex: charIndex,
          length: length - charIndex,
          isLastElement: true,
          addHyphenationSign: false,
          isStyleChange: isStyleChange,
          style: getTextStyle(),
          element: element,
          startX: realX,
          startY: realX + width - 1,
          endX: realY - height + 1,
          endY: realY + descent,
        ));
        isStyleChange = false;
        isWordOccurred = true;
      } else if (isStyleElement(element)) {
        applyStyleElement(element);
        isStyleChange = true;
      }
      realX += width;
      charIndex = 0;
    }
  }

  /// 绘制页面
  void drawPage(TextCanvas canvas, TextPage page, List<int> labels) {
    // 绘制代码块背景
    _drawCodeBlockBackgrounds(canvas, page);

    for (int i = 0; i < page.textLineList.length; i++) {
      _drawTextLine(canvas, page, page.textLineList[i], labels[i], labels[i + 1]);
    }
  }

  /// 绘制代码块背景矩形
  void _drawCodeBlockBackgrounds(TextCanvas canvas, TextPage page) {
    final lines = page.textLineList;
    final textAreaW = getTextAreaWidth().toDouble();
    int i = 0;
    while (i < lines.length) {
      final bgColor = lines[i].startStyle.getBgColor();
      if (bgColor != null) {
        // 找连续的背景色行
        int j = i;
        while (j < lines.length && lines[j].startStyle.getBgColor() == bgColor) {
          j++;
        }
        // 计算背景区域
        final topY = lines[i].y.toDouble();
        final lastLine = lines[j - 1];
        final bottomY = (lastLine.y + lastLine.height + lastLine.descent).toDouble();
        final padding = 6.0;
        final rect = Rect.fromLTRB(
          -padding, topY - padding,
          textAreaW + padding, bottomY + padding,
        );
        final paint = Paint()..color = Color(bgColor);
        canvas.canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(4)),
          paint,
        );
        i = j;
      } else {
        i++;
      }
    }
  }

  void _drawTextLine(
      TextCanvas canvas, TextPage page, TextLine line, int fromArea, int toArea) {
    final paragraph = line.paragraphCursor;
    var areaIndex = fromArea;
    final endElementIndex = line.endElementIndex;
    var charIndex = line.realStartCharIndex;
    final pageAreas = page.textElementAreaVector.areas();

    if (toArea > pageAreas.length) return;

    for (var wordIndex = line.realStartElementIndex;
        wordIndex < endElementIndex && areaIndex < toArea;
        wordIndex++) {
      final element = paragraph.getElement(wordIndex);
      if (element == null) continue;
      final area = pageAreas[areaIndex];

      if (identical(element, area.element)) {
        ++areaIndex;
        if (area.isStyleChange) setTextStyle(area.style);

        final areaX = area.startX;
        final areaY = area.endY - getElementDescent(element) -
            getTextStyle().getVerticalAlign(getMetrics());

        if (element is TextWordElement) {
          canvas.drawString(
              areaX, areaY, element.data, element.offset + charIndex,
              element.length - charIndex);
        } else if (element is TextImageElement) {
          canvas.drawImage(areaX, areaY, element.image, getTextAreaSize());
        }
      }
      charIndex = 0;
    }
  }

  /// 完整绘制入口
  void drawPageFull(TextCanvas canvas, TextPage page) {
    preparePage(page);
    final labels = prepareTextArea(page);
    drawPage(canvas, page, labels);
  }

  // === 对外绘制接口 ===

  /// 绘制指定类型的页面到 Canvas
  /// 对应 Kotlin BaseTextEngine.draw → TextEngine.drawInternal
  void draw(ui.Canvas canvas, PageType pageType) {
    if (_textModel == null ||
        _textModel!.getChapterCount() == 0 ||
        _textPageController == null) {
      return;
    }

    // 根据类型获取页面
    final TextPage? page = switch (pageType) {
      PageType.previous => _textPageController!.prevPage(),
      PageType.current => _textPageController!.getCurrentPage(),
      PageType.next => _textPageController!.nextPage(),
    };

    if (page == null) return;

    // 绘制背景色
    final bgPaint = Paint()..color = Color(getTextConfig().getBgColor());
    canvas.drawRect(
      Rect.fromLTWH(0, 0, viewWidth.toDouble(), viewHeight.toDouble()),
      bgPaint,
    );

    // 偏移到文本区域
    canvas.save();
    canvas.translate(
      getTextConfig().getMarginLeft().toDouble(),
      getTextConfig().getMarginTop().toDouble(),
    );

    // 绘制页面内容
    final textCanvas = TextCanvas(paintContext, canvas);
    drawPageFull(textCanvas, page);

    canvas.restore();
  }
}
