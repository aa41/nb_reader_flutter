import '../../text/entity/text_content.dart';
import '../../text/tag/text_tag.dart';
import '../../text/tag/text_tag_type.dart';
import 'plain_text_format.dart';

/// TXT 文本内容解析器
/// 移植自 C++ TxtReader + TxtReaderCore + BookEncoder
/// 核心简化：Dart 直接输出 TextTag 列表，跳过 C++ 的二进制中间格式
class TxtReader {
  /// 解析文本内容为 TextTag 列表
  ///
  /// [text] 章节文本
  /// [format] 段落格式规则
  /// [hasTitleLine] 是否将第一行视为标题（非序章的章节为 true）
  static TextContent parse(
    String text,
    PlainTextFormat format, {
    bool hasTitleLine = false,
  }) {
    final tags = <TextTag>[];
    final lines = text.split(RegExp(r'\r?\n'));

    // --- 状态（对应 C++ TxtReader 成员变量）---
    final kindStack = <int>[TextControlType.regular];
    bool isTitleExist = hasTitleLine;
    bool isNewLine = true;
    bool isCurLineEmpty = true;
    int consecutiveEmptyLines = 0;
    int curLineSpaceCount = 0;
    bool isParagraphOpen = false;

    // --- beginParagraph：对应 BookEncoder.beginParagraph ---
    // 创建段落标签，并重新应用样式栈中所有控制标签
    void beginParagraph() {
      tags.add(const TextParagraphTag(TextParagraphType.textParagraph));
      for (final kind in kindStack) {
        tags.add(TextControlTag(kind, true));
      }
      isParagraphOpen = true;
    }

    // --- endParagraph：对应 TxtReader.endParagraph ---
    void endParagraph() {
      if (!isParagraphOpen) return;
      if (!isCurLineEmpty) {
        consecutiveEmptyLines = -1;
      }
      isCurLineEmpty = true;
      isParagraphOpen = false;
    }

    // --- createNewLine：对应 TxtReader.createNewLine ---
    void createNewLine() {
      if (!isCurLineEmpty) {
        consecutiveEmptyLines = -1;
      }
      isCurLineEmpty = true;
      isNewLine = true;
      curLineSpaceCount = 0;
      consecutiveEmptyLines++;

      bool paragraphBreak =
          (format.breakType & PlainTextFormat.breakParagraphAtNewLine) != 0 ||
              ((format.breakType &
                          PlainTextFormat.breakParagraphAtEmptyLine) !=
                      0 &&
                  consecutiveEmptyLines > 0);

      // 取消标题样式
      if (isTitleExist) {
        kindStack.removeLast();
        isTitleExist = false;
        paragraphBreak = true;
      }

      if (paragraphBreak) {
        endParagraph();
        beginParagraph();
      }
    }

    // --- receiveText：对应 TxtReader.receiveText ---
    void receiveText(String line) {
      // 统计前导空格
      int spaces = 0;
      for (int i = 0; i < line.length; i++) {
        final ch = line.codeUnitAt(i);
        if (ch == 0x20) {
          // 空格
          spaces++;
        } else if (ch == 0x09) {
          // tab
          spaces += format.ignoredIndent + 1;
        } else {
          break;
        }
      }
      curLineSpaceCount = spaces;

      final trimmed = line.trimLeft();
      if (trimmed.isNotEmpty) {
        isCurLineEmpty = false;

        // 缩进换段检测
        if ((format.breakType &
                    PlainTextFormat.breakParagraphAtLineWithIndent) !=
                0 &&
            isNewLine &&
            curLineSpaceCount > format.ignoredIndent) {
          endParagraph();
          beginParagraph();
        }

        // 添加文本内容（保留原始文本含前导空格，Phase 4 ParagraphContentDecoder 处理分词）
        tags.add(TextContentTag(line));
        isNewLine = false;
      }
    }

    // === 开始分析（对应 TxtReader.beginAnalyze）===
    if (isTitleExist) {
      kindStack.add(TextControlType.title);
    }
    beginParagraph();

    // === 处理每一行（对应 TxtReaderCore.readContent）===
    for (int i = 0; i < lines.length; i++) {
      if (i > 0) createNewLine();

      final line = lines[i].replaceAll('\r', '');
      if (line.isNotEmpty) {
        receiveText(line);
      }
    }

    // === 结束分析（对应 TxtReader.endAnalyze）===
    // 插入段落结束标记
    tags.add(
        const TextParagraphTag(TextParagraphType.endOfSectionParagraph));
    endParagraph();

    return TextContent(tags: tags);
  }
}
