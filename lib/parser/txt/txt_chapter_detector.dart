import '../../text/entity/text_chapter.dart';

/// TXT 章节探测器
/// 使用正则表达式匹配章节标题，分割文本为章节列表
class TxtChapterDetector {
  /// 默认章节匹配正则（匹配"第X章/节/回/集/卷"格式）
  static const String defaultPattern =
      r'^(.{0,8})(第)([0-9零一二两三四五六七八九十百千万壹贰参肆伍陆柒捌玖拾佰仟]{1,10})([章节回集卷])(.{0,30})$';

  /// 最小章节内容长度（字符数）
  static const int _minChapterContentSize = 40;

  /// 探测章节
  /// [text] 已解码的全文本
  /// [filePath] 文件路径
  /// [pattern] 章节正则，默认使用 defaultPattern
  /// [prologueTitle] 序章标题
  static List<TextChapter> detect(
    String text,
    String filePath, {
    String? pattern,
    String prologueTitle = '开始',
  }) {
    final regex = RegExp(pattern ?? defaultPattern, multiLine: true);
    final matches = regex.allMatches(text).toList();

    if (matches.isEmpty) {
      // 没有匹配到章节，整个文件作为一个章节
      return [
        TextChapter(
          url: filePath,
          title: prologueTitle,
          startIndex: 0,
          endIndex: text.length,
        ),
      ];
    }

    final chapters = <TextChapter>[];

    for (int i = 0; i < matches.length; i++) {
      final match = matches[i];
      final titleStart = match.start;
      final title = match.group(0)!.trim();

      // 处理序章（第一个章节标题之前的内容）
      if (i == 0 && titleStart > 0) {
        if (titleStart >= _minChapterContentSize) {
          chapters.add(TextChapter(
            url: filePath,
            title: prologueTitle,
            startIndex: 0,
            endIndex: titleStart,
          ));
        }
      }

      // 当前章节
      final startIndex = titleStart;
      final endIndex =
          (i + 1 < matches.length) ? matches[i + 1].start : text.length;

      chapters.add(TextChapter(
        url: filePath,
        title: title,
        startIndex: startIndex,
        endIndex: endIndex,
      ));
    }

    // 合并过短的章节到前一章
    final result = <TextChapter>[];
    for (final chapter in chapters) {
      final len = chapter.endIndex - chapter.startIndex;
      if (len < _minChapterContentSize && result.isNotEmpty) {
        final prev = result.removeLast();
        result.add(TextChapter(
          url: prev.url,
          title: prev.title,
          startIndex: prev.startIndex,
          endIndex: chapter.endIndex,
        ));
      } else {
        result.add(chapter);
      }
    }

    // 如果序章被跳过（太短），将其内容合并到第一章
    if (matches.first.start > 0 &&
        matches.first.start < _minChapterContentSize &&
        result.isNotEmpty) {
      final first = result.removeAt(0);
      result.insert(
        0,
        TextChapter(
          url: first.url,
          title: first.title,
          startIndex: 0,
          endIndex: first.endIndex,
        ),
      );
    }

    return result;
  }
}
