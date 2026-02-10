/// 纯文本格式参数（控制段落分割行为）
class PlainTextFormat {
  /// 段落分割条件（可按位 OR 组合）
  static const int breakParagraphAtNewLine = 1;
  static const int breakParagraphAtEmptyLine = 2;
  static const int breakParagraphAtLineWithIndent = 4;

  /// 段落分割规则（位掩码）
  final int breakType;

  /// 忽略的缩进大小（小于等于此缩进不触发缩进换段）
  final int ignoredIndent;

  const PlainTextFormat({
    this.breakType = breakParagraphAtNewLine,
    this.ignoredIndent = 1,
  });

  @override
  String toString() =>
      'PlainTextFormat(breakType=$breakType, ignoredIndent=$ignoredIndent)';
}

/// 纯文本格式探测器
/// 分析文本统计信息，自动确定最佳的段落分割策略
/// 移植自 C++ PlainTextDetector::detect()
class PlainTextDetector {
  static const int _maxDetectSize = 1024 * 1024; // 1 MB

  /// 探测文本格式
  static PlainTextFormat detect(String text) {
    final int detectLen =
        text.length < _maxDetectSize ? text.length : _maxDetectSize;

    const int tableSize = 10;

    int lineCounter = 0;
    int emptyLineCounter = 0;
    int stringsWithLengthLessThan81 = 0;
    final stringIndentTable = List<int>.filled(tableSize, 0);

    bool currentLineIsEmpty = true;
    int currentLineLength = 0;
    int currentLineIndent = 0;

    for (int i = 0; i < detectLen; i++) {
      final ch = text.codeUnitAt(i);
      currentLineLength++;

      if (ch == 0x0A) {
        // \n
        lineCounter++;
        if (currentLineIsEmpty) emptyLineCounter++;
        if (currentLineLength < 81) stringsWithLengthLessThan81++;
        if (!currentLineIsEmpty) {
          final idx =
              currentLineIndent < tableSize ? currentLineIndent : tableSize - 1;
          stringIndentTable[idx]++;
        }
        currentLineIsEmpty = true;
        currentLineLength = 0;
        currentLineIndent = 0;
      } else if (ch == 0x0D) {
        // \r 忽略
        continue;
      } else if (ch == 0x20 || ch == 0x09) {
        // 空格或 tab
        if (currentLineIsEmpty) currentLineIndent++;
      } else {
        currentLineIsEmpty = false;
      }
    }

    final int nonEmptyLineCounter = lineCounter - emptyLineCounter;

    // 检测是否为 CJK 为主的文本（中文/日文/韩文）
    int cjkCharCount = 0;
    int totalNonSpaceCharCount = 0;
    final int cjkDetectLen = detectLen < 10000 ? detectLen : 10000;
    for (int i = 0; i < cjkDetectLen; i++) {
      final ch = text.codeUnitAt(i);
      if (ch > 0x20 && ch != 0x3000) {
        totalNonSpaceCharCount++;
        if (_isCJK(ch)) cjkCharCount++;
      }
    }
    final bool isCJKDominant = totalNonSpaceCharCount > 0 &&
        cjkCharCount > totalNonSpaceCharCount * 0.3;

    // 计算忽略缩进距离
    int ignoredIndent = 1;
    {
      int lineWithIndent = 0;
      for (int indent = 0; indent < tableSize; indent++) {
        lineWithIndent += stringIndentTable[indent];
        if (nonEmptyLineCounter > 0 &&
            lineWithIndent > 0.1 * nonEmptyLineCounter) {
          ignoredIndent = indent + 1;
          break;
        }
      }
    }

    // 确定分割类型
    int breakType = PlainTextFormat.breakParagraphAtEmptyLine;
    if (isCJKDominant) {
      // CJK 文本：每行通常是一个段落
      breakType |= PlainTextFormat.breakParagraphAtNewLine;
    } else if (nonEmptyLineCounter > 0 &&
        stringsWithLengthLessThan81 < 0.3 * nonEmptyLineCounter) {
      breakType |= PlainTextFormat.breakParagraphAtNewLine;
    } else {
      breakType |= PlainTextFormat.breakParagraphAtLineWithIndent;
    }

    return PlainTextFormat(breakType: breakType, ignoredIndent: ignoredIndent);
  }

  /// 判断是否为 CJK 字符
  static bool _isCJK(int ch) {
    return (ch >= 0x4E00 && ch <= 0x9FFF) ||   // CJK Unified Ideographs
        (ch >= 0x3400 && ch <= 0x4DBF) ||      // CJK Extension A
        (ch >= 0x3000 && ch <= 0x303F) ||      // CJK Symbols and Punctuation
        (ch >= 0x3040 && ch <= 0x309F) ||      // Hiragana
        (ch >= 0x30A0 && ch <= 0x30FF) ||      // Katakana
        (ch >= 0xAC00 && ch <= 0xD7AF) ||      // Hangul Syllables
        (ch >= 0xFF00 && ch <= 0xFFEF) ||      // Fullwidth Forms
        (ch >= 0xFE30 && ch <= 0xFE4F);        // CJK Compatibility Forms
  }
}
