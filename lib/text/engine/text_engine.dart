import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../config/text_config.dart';
import '../element/text_checkbox_element.dart';
import '../element/text_code_block_element.dart';
import '../element/text_control_element.dart';
import '../element/text_element.dart';
import '../element/text_horizontal_rule_element.dart';
import '../element/text_image_element.dart';
import '../element/text_table_element.dart';
import '../element/text_word_element.dart';
import '../entity/text_element_area.dart';
import '../entity/text_line.dart';
import '../entity/text_page.dart';
import '../search/text_search_engine.dart';
import '../style/text_alignment_type.dart';
import '../tag/text_tag.dart';
import '../tag/text_tag_type.dart';
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

  /// 搜索高亮关键词（null 表示无高亮）
  String? _highlightKeyword;

  /// 搜索高亮的精确位置（对应关键词起始位置）
  TextFixedPosition? _highlightPosition;

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
      // 搜索高亮期间优先使用高亮位置，避免 safeTop 等配置变化触发的
      // 重新分页将位置回退到页面起始处（而非搜索结果位置）。
      if (_highlightPosition != null) {
        savedTextPos = _highlightPosition;
      } else {
        final curPage = _textPageController!.getCurrentPage();
        if (curPage != null) {
          savedTextPos = TextFixedPosition.fromPosition(curPage.startWordCursor);
        }
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
        if (remainAreaHeight <= 0) {
          // 尝试分割代码块：如果该行包含超高代码块，计算可容纳的行数
          final availableH = (remainAreaHeight + curLine.height + curLine.descent).toDouble();
          final splitLine = _trySplitCodeBlockInLine(
              paragraphCursor, curLine, availableH);
          if (splitLine != null) {
            // 光标停在代码块元素上，charIndex = 下一页的起始行号
            findCursor.moveTo(splitLine.$1, splitLine.$2);
          } else if (findCursor.compareTo(startWordCursor) > 0) {
            // 无法分割但页面已有内容 → 在代码块前结束页面，
            // 让代码块在下一页以完整页面高度开始。
            // findCursor 已在代码块前的位置，无需移动。
          } else {
            // 页面无其他内容，必须包含超大元素（裁剪显示）以防止死循环
            findCursor.moveTo(curLine.endElementIndex, curLine.endCharIndex);
          }
          break;
        }
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

  /// 尝试将代码块拆分到当前页面内可容纳的行数。
  /// 返回 (elementIndex, nextStartLine)，表示下一页从代码块的第 nextStartLine 行开始；
  /// 返回 null 表示无法拆分（没有代码块，或一行都放不下）。
  (int, int)? _trySplitCodeBlockInLine(
      TextParagraphCursor paragraphCursor, TextLine line, double availableHeight) {
    for (int i = line.realStartElementIndex; i < line.endElementIndex; i++) {
      final element = paragraphCursor.getElement(i);
      if (element is TextCodeBlockElement) {
        final startLine =
            (i == line.realStartElementIndex) ? line.realStartCharIndex : 0;
        final fittingLines =
            _calcFittingCodeLines(element, startLine, availableHeight);
        if (fittingLines > 0 && startLine + fittingLines < element.lines.length) {
          return (i, startLine + fittingLines);
        }
        return null;
      }
    }
    return null;
  }

  /// 计算在 availableHeight 高度内可容纳的代码行数（从 startLine 开始）。
  int _calcFittingCodeLines(
      TextCodeBlockElement element, int startLine, double availableHeight) {
    final langH =
        (startLine == 0 && element.language != null && element.language!.isNotEmpty)
            ? TextCodeBlockElement.langLabelHeight
            : 0;
    final fixedOverhead = TextCodeBlockElement.outerMarginV * 2 +
        TextCodeBlockElement.paddingV * 2 +
        langH;
    final availableForLines = availableHeight - fixedOverhead;
    if (availableForLines <= 0) return 0;

    final codeMaxWidth =
        getTextAreaWidth().toDouble() - TextCodeBlockElement.paddingH * 2;
    final wrappedCounts = element.getWrappedLineCounts(
        codeMaxWidth > 0 ? codeMaxWidth : double.infinity);

    int fittingLines = 0;
    double usedHeight = 0;
    for (int i = startLine; i < wrappedCounts.length; i++) {
      final lineHeight =
          wrappedCounts[i] * TextCodeBlockElement.codeLineHeight;
      if (usedHeight + lineHeight > availableForLines) break;
      usedHeight += lineHeight;
      fittingLines++;
    }
    return fittingLines;
  }

  /// 准备页面（生成 TextLine 列表）
  void preparePage(TextPage page) {
    if (page.isPrepare) return;

    final pageStartCursor = page.startWordCursor;
    final pageEndCursor = page.endWordCursor;
    final findCursor = TextWordCursor.copy(pageStartCursor);
    final textLines = page.textLineList;
    TextLine? curLine;

    while (findCursor.compareTo(pageEndCursor) < 0) {
      resetTextStyle();
      final preLine = curLine;
      final paragraphCursor = findCursor.getParagraphCursor();
      final curElementIndex = findCursor.elementIndex;

      var endElementIndex =
          (identical(paragraphCursor, pageEndCursor.getParagraphCursor()) ||
                  paragraphCursor.paragraphIndex ==
                      pageEndCursor.paragraphIndex &&
                  paragraphCursor.chapterIndex ==
                      pageEndCursor.chapterIndex)
              ? pageEndCursor.elementIndex
              : paragraphCursor.getElementCount();

      // 代码块分页：如果页面结束于代码块中间（charIndex > 0），
      // 需要将 endElementIndex 加 1 以包含该代码块元素
      if (endElementIndex < paragraphCursor.getElementCount() &&
          pageEndCursor.charIndex > 0) {
        final endElem = paragraphCursor.getElement(endElementIndex);
        if (endElem is TextCodeBlockElement) {
          endElementIndex++;
        }
      }

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
      } else if (element is TextCodeBlockElement ||
                 element is TextTableElement ||
                 element is TextHorizontalRuleElement ||
                 element is TextCheckboxElement) {
        // 块级元素必须标记为可见，否则不会被绘制
        wordOccurred = true;
        isVisible = true;
      } else if (isStyleElement(element)) {
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

    // 段后间距
    if (curLineInfo.isEndOfParagraph()) {
      curLineInfo.vSpaceAfter = getTextStyle().getSpaceAfter(getMetrics());
    }

    // 检测引用块深度：扫描段落元素中的 blockquote ControlElement
    // 使用 realStartElementIndex（行可见内容起始前），避免扫到段落末尾的 CLOSE 标签
    // 导致最后一行（换行后）深度归零、背景消失
    int bqDepth = 0;
    for (int i = 0; i < curLineInfo.realStartElementIndex; i++) {
      final e = paragraphCursor.getElement(i);
      if (e is TextControlElement && e.type == TextControlType.blockquote) {
        bqDepth += e.isStart ? 1 : -1;
      }
    }
    curLineInfo.blockquoteDepth = bqDepth.clamp(0, 10);

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
      } else if (element is TextCodeBlockElement ||
                 element is TextTableElement ||
                 element is TextHorizontalRuleElement ||
                 element is TextCheckboxElement) {
        // ★ 块级元素：必须加入 area vector，否则 _drawTextLine 无法找到并绘制它们
        // 块级元素始终从 x=0 开始，忽略 leftIndent
        final height = getElementHeight(element);
        page.textElementAreaVector.add(TextElementArea(
          chapterIndex: chapterIdx,
          paragraphIndex: paragraphIdx,
          elementIndex: wordIndex,
          charIndex: charIndex,
          length: 0,
          isLastElement: true,
          addHyphenationSign: false,
          isStyleChange: isStyleChange,
          style: getTextStyle(),
          element: element,
          startX: 0,                     // 块级元素从左边缘开始
          startY: width - 1,             // 右边缘
          endX: y,                        // 上边缘（行顶部）
          endY: y + height,              // 下边缘
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
    // 预先绘制引用块背景（在文字之下）
    _drawBlockquoteBackgrounds(canvas, page);

    for (int i = 0; i < page.textLineList.length; i++) {
      _drawTextLine(canvas, page, page.textLineList[i], labels[i], labels[i + 1]);
    }
  }

  /// 绘制引用块背景（微信公众号风格：浅灰背景 + 绿色左边框）
  void _drawBlockquoteBackgrounds(TextCanvas canvas, TextPage page) {
    int y = 0;
    for (int i = 0; i < page.textLineList.length; i++) {
      final line = page.textLineList[i];
      final lineH = line.height + line.descent + line.vSpaceAfter;
      if (line.blockquoteDepth > 0) {
        canvas.drawBlockBackground(
          rect: Rect.fromLTWH(
            0, y.toDouble(),
            getTextAreaWidth().toDouble(), lineH.toDouble(),
          ),
          bgColor: const Color(0xFFF9F9F9),
          borderLeftColor: const Color(0xFF76B947),
          borderLeftWidth: 3,
        );
      }
      y += lineH;
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
        } else if (element is TextHorizontalRuleElement) {
          // 分割线：块级元素，使用 area.endX (=y顶部) 定位
          final blockTop = area.endX.toDouble();
          final blockH = getElementHeight(element).toDouble();
          final centerY = (blockTop + blockH / 2).toInt();
          canvas.drawHorizontalRule(0, centerY, getTextAreaWidth());
        } else if (element is TextCodeBlockElement) {
          // 代码块占位符卡片：使用 area.endX (=y顶部) 定位
          final blockTop = area.endX.toDouble();
          final totalH = getElementHeight(element).toDouble();
          final margin = TextCodeBlockElement.outerMarginV.toDouble();
          final blockRect = Rect.fromLTWH(
            0, blockTop + margin,
            getTextAreaWidth().toDouble(), totalH - margin * 2,
          );
          canvas.drawCodeBlock(rect: blockRect, element: element);
        } else if (element is TextTableElement) {
          // 表格：块级元素，使用 area.endX (=y顶部) 定位
          final blockTop = area.endX.toDouble();
          final totalH = getElementHeight(element).toDouble();
          final margin = TextTableElement.outerMarginV.toDouble();
          final tableRect = Rect.fromLTWH(
            0, blockTop + margin,
            getTextAreaWidth().toDouble(), totalH - margin * 2,
          );
          final colW = getTextAreaWidth().toDouble() / element.columnCount;
          final colWidths = List.filled(element.columnCount, colW);
          canvas.drawTable(
            rect: tableRect,
            element: element,
            colWidths: colWidths,
          );
        } else if (element is TextCheckboxElement) {
          canvas.drawCheckbox(areaX, areaY, element.checked);
        }
      }
      charIndex = 0;
    }
  }

  /// 设置搜索高亮结果（关键词 + 精确位置）
  void setHighlightResult(String keyword, TextFixedPosition position) {
    _highlightKeyword = keyword;
    _highlightPosition = position;
  }

  /// 清除搜索高亮
  void clearHighlightResult() {
    _highlightKeyword = null;
    _highlightPosition = null;
  }

  /// 获取搜索高亮关键词
  String? get highlightKeyword => _highlightKeyword;

  /// 查找给定屏幕坐标处的链接 URL
  /// [localX], [localY] 是相对于 Widget 左上角的坐标
  /// 返回链接 URL，如果点击位置不在链接上则返回 null
  String? findLinkAtPosition(double localX, double localY) {
    if (_textModel == null || _textPageController == null) return null;
    final page = _textPageController!.getCurrentPage();
    if (page == null || !page.isPrepare) return null;

    // 转换为文本区域坐标
    final textX = localX - getTextConfig().getMarginLeft();
    final textY = localY - getTextConfig().getMarginTop();
    if (textX < 0 || textY < 0) return null;

    // 查找被点击的 TextElementArea
    final areas = page.textElementAreaVector.areas();
    TextElementArea? hitArea;
    for (final area in areas) {
      // area 坐标：startX=左边, startY=右边, endX=上边, endY=下边
      final left = area.startX.toDouble();
      final right = (area.startY + 1).toDouble();
      final top = area.endX.toDouble();
      final bottom = area.endY.toDouble();
      if (textX >= left && textX <= right && textY >= top && textY <= bottom) {
        hitArea = area;
        break;
      }
    }
    if (hitArea == null) return null;

    // 扫描段落的 tag 流，跟踪链接状态直到 hitArea.elementIndex
    final chapterCursor = _textModel!.getChapterCursor(hitArea.chapterIndex);
    final tagIter2 = chapterCursor.getParagraphContent(hitArea.paragraphIndex);
    String? activeLinkUrl;
    // 遍历 tags 跟踪链接状态和元素位置
    int tagElementIndex = -1; // 当前 tag 对应的元素索引
    while (tagIter2.hasNext()) {
      final tag = tagIter2.next();
      if (tag is TextLinkStartTag) {
        activeLinkUrl = tag.url;
      } else if (tag is TextLinkEndTag) {
        activeLinkUrl = null;
      }
      // 跟踪元素索引：只有生成元素的 tag 才递增
      if (tag is TextContentTag ||
          tag is TextImageTag ||
          tag is TextControlTag ||
          tag is TextCssStyleTag ||
          tag is TextOtherStyleTag ||
          tag is TextStyleCloseTag ||
          tag is TextFixedHSpaceTag ||
          tag is TextHorizontalRuleTag ||
          tag is TextCodeBlockTag ||
          tag is TextTableTag ||
          tag is TextBlockquoteStartTag ||
          tag is TextBlockquoteEndTag) {
        tagElementIndex++;
      }
      if (tagElementIndex >= hitArea.elementIndex) break;
    }

    return activeLinkUrl;
  }

  /// 查找给定屏幕坐标处的代码块元素
  TextCodeBlockElement? findCodeBlockAtPosition(double localX, double localY) {
    final area = _findHitArea(localX, localY);
    if (area == null) return null;
    final elem = area.element;
    return elem is TextCodeBlockElement ? elem : null;
  }

  /// 查找给定屏幕坐标处的图片元素
  TextImageElement? findImageAtPosition(double localX, double localY) {
    final area = _findHitArea(localX, localY);
    if (area == null) return null;
    final elem = area.element;
    return elem is TextImageElement ? elem : null;
  }

  /// 查找给定屏幕坐标处的 TextElementArea（通用 hit 测试）
  TextElementArea? _findHitArea(double localX, double localY) {
    if (_textModel == null || _textPageController == null) return null;
    final page = _textPageController!.getCurrentPage();
    if (page == null || !page.isPrepare) return null;

    final textX = localX - getTextConfig().getMarginLeft();
    final textY = localY - getTextConfig().getMarginTop();
    if (textX < 0 || textY < 0) return null;

    final areas = page.textElementAreaVector.areas();
    for (final area in areas) {
      final left = area.startX.toDouble();
      final right = (area.startY + 1).toDouble();
      final top = area.endX.toDouble();
      final bottom = area.endY.toDouble();
      if (textX >= left && textX <= right && textY >= top && textY <= bottom) {
        return area;
      }
    }
    return null;
  }

  /// 完整绘制入口
  /// [drawHighlight] 仅当前页传 true，前后页传 false
  void drawPageFull(TextCanvas canvas, TextPage page, {bool drawHighlight = false}) {
    preparePage(page);
    final labels = prepareTextArea(page);
    // 仅在当前页绘制搜索高亮
    if (drawHighlight && _highlightKeyword != null && _highlightKeyword!.isNotEmpty) {
      _drawSearchHighlights(canvas, page, labels);
    }
    drawPage(canvas, page, labels);
  }

  /// 绘制搜索高亮（仅高亮特定搜索结果，而非页面上所有关键词匹配）
  /// 通过 _highlightPosition 找到匹配起始的 TextElementArea，
  /// 然后向前遍历 keyword.length 个字符的区域进行高亮。
  void _drawSearchHighlights(TextCanvas canvas, TextPage page, List<int> labels) {
    final pos = _highlightPosition;
    final keyword = _highlightKeyword;
    if (pos == null || keyword == null || keyword.isEmpty) return;

    final areas = page.textElementAreaVector.areas();

    // 查找匹配起始的 TextElementArea
    int startAreaIdx = -1;
    for (int i = 0; i < areas.length; i++) {
      final area = areas[i];
      if (area.element is TextWordElement &&
          area.paragraphIndex == pos.paragraphIndex &&
          area.elementIndex == pos.elementIndex &&
          area.charIndex <= pos.charIndex &&
          pos.charIndex < area.charIndex + area.length) {
        startAreaIdx = i;
        break;
      }
    }

    if (startAreaIdx == -1) return;

    final highlightPaint = Paint()
      ..color = Color(getTextConfig().searchHighlightColor)
      ..style = PaintingStyle.fill;

    // 从起始 area 向前遍历，高亮覆盖 keyword.length 个字符的区域
    int charsRemaining = keyword.length;
    int prevEndElementIndex = -1;

    for (int i = startAreaIdx; i < areas.length && charsRemaining > 0; i++) {
      final area = areas[i];
      if (area.element is! TextWordElement) continue;
      if (area.paragraphIndex != pos.paragraphIndex) break;

      // 累计相邻 word area 之间的空白字符（hSpace）
      if (prevEndElementIndex >= 0 &&
          area.elementIndex > prevEndElementIndex) {
        charsRemaining -= 1;
        if (charsRemaining <= 0) break;
      }

      final int charsInArea;
      if (i == startAreaIdx) {
        // 首个 area：从匹配起始位置开始计数
        charsInArea = (area.charIndex + area.length) - pos.charIndex;
      } else {
        charsInArea = area.length;
      }

      // 绘制高亮矩形
      final left = area.startX.toDouble();
      final right = (area.startY + 1).toDouble();
      final top = area.endX.toDouble();
      final bottom = area.endY.toDouble();
      canvas.canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(left - 1, top - 1, right + 1, bottom + 1),
          const Radius.circular(2),
        ),
        highlightPaint,
      );

      charsRemaining -= charsInArea;
      prevEndElementIndex = area.elementIndex + 1;
    }
  }

  // === 对外绘制接口 ===

  /// 绘制指定类型的页面到 Canvas
  /// 对应 Kotlin BaseTextEngine.draw → TextEngine.drawInternal
  /// 注意：搜索高亮不在此处绘制，而是通过 drawHighlightOverlay 独立绘制，
  /// 避免高亮被烘焙进 Picture 缓存导致翻页时出现错误的高亮。
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

    // 绘制页面内容（不含搜索高亮）
    final textCanvas = TextCanvas(paintContext, canvas);
    drawPageFull(textCanvas, page, drawHighlight: false);

    canvas.restore();
  }

  /// 将 SearchPosition 解析为精确的 TextFixedPosition
  ///
  /// 两阶段策略：
  ///   1. 遍历段落 tags 构建 ContentTag 偏移表，找到目标 ContentTag 及标签内偏移
  ///   2. 遍历元素，通过 WordElement.data 引用识别 ContentTag 边界，
  ///      找到目标 ContentTag 内包含该偏移的元素
  TextFixedPosition resolveSearchPosition(SearchPosition searchPos) {
    final fallback = TextFixedPosition(
      chapterIndex: searchPos.chapterIndex,
      paragraphIndex: searchPos.paragraphIndex,
      elementIndex: 0,
      charIndex: 0,
    );

    if (_textModel == null) return fallback;

    final chapterCursor = _textModel!.getChapterCursor(searchPos.chapterIndex);
    if (searchPos.paragraphIndex >= chapterCursor.getParagraphCount()) {
      return fallback;
    }

    final paragraphCursor =
        chapterCursor.getParagraphCursor(searchPos.paragraphIndex);
    final tagIter =
        chapterCursor.getParagraphContent(searchPos.paragraphIndex);

    // ── 第一阶段：遍历 tags，构建 ContentTag 偏移表 ──
    final contentTagOffsets = <int>[]; // 每个 ContentTag 在段落纯文本中的起始偏移
    final contentTagLens = <int>[];    // 每个 ContentTag 的字符长度
    int textOff = 0;

    while (tagIter.hasNext()) {
      final tag = tagIter.next();
      if (tag is TextContentTag) {
        contentTagOffsets.add(textOff);
        contentTagLens.add(tag.content.length);
        textOff += tag.content.length;
      }
    }

    // 找到目标偏移所在的 ContentTag
    int targetCTIndex = -1;
    int offsetInTag = 0;
    for (int i = 0; i < contentTagOffsets.length; i++) {
      if (contentTagOffsets[i] + contentTagLens[i] >
          searchPos.charOffsetInParagraph) {
        targetCTIndex = i;
        offsetInTag = searchPos.charOffsetInParagraph - contentTagOffsets[i];
        break;
      }
    }

    if (targetCTIndex < 0) return fallback;

    // ── 第二阶段：遍历元素，通过 data 引用跟踪 ContentTag 边界 ──
    // 同一 ContentTag 的所有 WordElement 共享相同的 data 引用
    // （_processContentTag 中 contentCodes = content.codeUnits 只创建一次）
    int currentCTIndex = -1;
    Object? currentData;

    for (int i = 0; i < paragraphCursor.getElementCount(); i++) {
      final elem = paragraphCursor.getElement(i);

      if (elem is TextWordElement) {
        // 检测 ContentTag 边界：data 引用变化表示进入新的 ContentTag
        if (currentData == null || !identical(elem.data, currentData)) {
          currentCTIndex++;
          currentData = elem.data;
        }

        if (currentCTIndex == targetCTIndex) {
          if (offsetInTag >= elem.offset &&
              offsetInTag < elem.offset + elem.length) {
            return TextFixedPosition(
              chapterIndex: searchPos.chapterIndex,
              paragraphIndex: searchPos.paragraphIndex,
              elementIndex: i,
              charIndex: offsetInTag - elem.offset,
            );
          }
          if (elem.offset > offsetInTag) {
            // 偏移落在空白区域，对齐到最近的单词元素
            return TextFixedPosition(
              chapterIndex: searchPos.chapterIndex,
              paragraphIndex: searchPos.paragraphIndex,
              elementIndex: i,
              charIndex: 0,
            );
          }
        }

        if (currentCTIndex > targetCTIndex) break;
      }
    }

    return fallback;
  }

  /// 绘制搜索高亮覆盖层（仅绘制当前页的高亮）
  /// 此方法由动画系统在空闲状态下调用，独立于 Picture 缓存，
  /// 确保高亮仅出现在当前可见页面上。
  void drawHighlightOverlay(ui.Canvas canvas) {
    if (_highlightKeyword == null || _highlightKeyword!.isEmpty) return;
    if (_textModel == null || _textPageController == null) return;

    final page = _textPageController!.getCurrentPage();
    if (page == null) return;

    canvas.save();
    canvas.translate(
      getTextConfig().getMarginLeft().toDouble(),
      getTextConfig().getMarginTop().toDouble(),
    );

    preparePage(page);
    final labels = prepareTextArea(page);
    final textCanvas = TextCanvas(paintContext, canvas);
    _drawSearchHighlights(textCanvas, page, labels);

    canvas.restore();
  }
}
