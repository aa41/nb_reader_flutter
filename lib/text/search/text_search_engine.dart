import 'dart:async';
import 'dart:isolate';

import '../../parser/format_plugin.dart';
import '../tag/text_tag.dart';
import '../tag/text_tag_type.dart';

/// 搜索位置（中间结果，需通过 TextEngine.resolveSearchPosition 转为精确 TextFixedPosition）
class SearchPosition {
  /// 章节索引
  final int chapterIndex;

  /// 段落索引
  final int paragraphIndex;

  /// 关键词在段落纯文本中的字符偏移
  final int charOffsetInParagraph;

  const SearchPosition({
    required this.chapterIndex,
    required this.paragraphIndex,
    required this.charOffsetInParagraph,
  });
}

/// 搜索结果
class SearchResult {
  /// 章节索引
  final int chapterIndex;

  /// 章节标题
  final String chapterTitle;

  /// 匹配文本上下文（关键词 ± 周围文字）
  final String contextText;

  /// 关键词在 contextText 中的起始偏移
  final int keywordStartInContext;

  /// 搜索关键词
  final String keyword;

  /// 关键词在章节纯文本中的字符偏移
  final int matchOffset;

  const SearchResult({
    required this.chapterIndex,
    required this.chapterTitle,
    required this.contextText,
    required this.keywordStartInContext,
    required this.keyword,
    required this.matchOffset,
  });
}

/// 搜索进度事件
class SearchProgress {
  /// 当前搜索到的章节索引
  final int currentChapterIndex;

  /// 总章节数
  final int totalChapters;

  /// 是否完成
  final bool isComplete;

  const SearchProgress({
    required this.currentChapterIndex,
    required this.totalChapters,
    required this.isComplete,
  });
}

/// 搜索事件（结果或进度）
class SearchEvent {
  final SearchResult? result;
  final SearchProgress? progress;

  const SearchEvent.result(this.result) : progress = null;
  const SearchEvent.progress(this.progress) : result = null;
}

/// Isolate 搜索任务参数
class _SearchParams {
  final String keyword;
  final List<_ChapterData> chapters;
  final SendPort sendPort;
  final bool caseSensitive;

  const _SearchParams({
    required this.keyword,
    required this.chapters,
    required this.sendPort,
    required this.caseSensitive,
  });
}

/// 序列化的章节数据（传递给 Isolate）
class _ChapterData {
  final int index;
  final String title;
  final String plainText;

  const _ChapterData({
    required this.index,
    required this.title,
    required this.plainText,
  });
}

/// 全文搜索引擎
/// 使用 Isolate 在后台线程执行搜索，通过 Stream 流式返回结果
class TextSearchEngine {
  final FormatPlugin _plugin;

  /// 预缓存的章节纯文本
  List<_ChapterData>? _cachedChapterData;

  /// 当前活跃的 Isolate
  Isolate? _isolate;
  ReceivePort? _receivePort;

  /// 是否已释放
  bool _disposed = false;

  TextSearchEngine(this._plugin);

  /// 预加载所有章节纯文本到内存
  /// 建议在打开书籍后调用一次，后续搜索直接使用缓存
  Future<void> preloadChapterTexts() async {
    if (_cachedChapterData != null) return;

    final chapters = _plugin.getChapters();
    final data = <_ChapterData>[];

    for (int i = 0; i < chapters.length; i++) {
      final plainText = _plugin.getChapterPlainText(chapters[i]);
      if (plainText != null && plainText.isNotEmpty) {
        data.add(_ChapterData(
          index: i,
          title: chapters[i].title,
          plainText: plainText,
        ));
      }
    }

    _cachedChapterData = data;
  }

  /// 流式搜索，返回搜索事件流（包含搜索结果和进度）。
  /// 每次调用会自动取消上一次搜索。
  Stream<SearchEvent> search(String keyword, {bool caseSensitive = false}) async* {
    // 取消上一次搜索
    _cancelCurrentSearch();

    if (keyword.isEmpty || _disposed) return;

    // 确保缓存已加载
    await preloadChapterTexts();
    if (_cachedChapterData == null || _cachedChapterData!.isEmpty) return;

    final receivePort = ReceivePort();
    _receivePort = receivePort;

    final params = _SearchParams(
      keyword: keyword,
      chapters: _cachedChapterData!,
      sendPort: receivePort.sendPort,
      caseSensitive: caseSensitive,
    );

    _isolate = await Isolate.spawn(_searchInIsolate, params);

    await for (final message in receivePort) {
      if (_disposed) break;

      if (message == null) {
        // Isolate 完成信号
        break;
      }

      if (message is Map<String, dynamic>) {
        if (message['type'] == 'result') {
          yield SearchEvent.result(SearchResult(
            chapterIndex: message['chapterIndex'] as int,
            chapterTitle: message['chapterTitle'] as String,
            contextText: message['contextText'] as String,
            keywordStartInContext: message['keywordStartInContext'] as int,
            keyword: message['keyword'] as String,
            matchOffset: message['matchOffset'] as int,
          ));
        } else if (message['type'] == 'progress') {
          yield SearchEvent.progress(SearchProgress(
            currentChapterIndex: message['currentChapterIndex'] as int,
            totalChapters: message['totalChapters'] as int,
            isComplete: message['isComplete'] as bool,
          ));
        }
      }
    }

    _cleanupIsolate();
  }

  /// 在 Isolate 中执行搜索（静态方法）
  static void _searchInIsolate(_SearchParams params) {
    final keyword = params.caseSensitive
        ? params.keyword
        : params.keyword.toLowerCase();
    final chapters = params.chapters;
    final sendPort = params.sendPort;

    for (int i = 0; i < chapters.length; i++) {
      final chapter = chapters[i];
      final text = params.caseSensitive
          ? chapter.plainText
          : chapter.plainText.toLowerCase();
      final originalText = chapter.plainText;

      // 逐个匹配
      int searchFrom = 0;
      while (true) {
        final matchIndex = text.indexOf(keyword, searchFrom);
        if (matchIndex == -1) break;

        // 提取上下文（前后各 30 字符）
        const contextRadius = 30;
        final contextStart = (matchIndex - contextRadius).clamp(0, originalText.length);
        final contextEnd = (matchIndex + keyword.length + contextRadius)
            .clamp(0, originalText.length);
        final contextText = originalText.substring(contextStart, contextEnd);
        final keywordStartInContext = matchIndex - contextStart;

        sendPort.send({
          'type': 'result',
          'chapterIndex': chapter.index,
          'chapterTitle': chapter.title,
          'contextText': contextText,
          'keywordStartInContext': keywordStartInContext,
          'keyword': params.keyword,
          'matchOffset': matchIndex,
        });

        searchFrom = matchIndex + keyword.length;
      }

      // 发送进度
      sendPort.send({
        'type': 'progress',
        'currentChapterIndex': i + 1,
        'totalChapters': chapters.length,
        'isComplete': i == chapters.length - 1,
      });
    }

    // 完成信号
    sendPort.send(null);
  }

  /// 取消当前搜索
  void _cancelCurrentSearch() {
    _cleanupIsolate();
  }

  void _cleanupIsolate() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _receivePort?.close();
    _receivePort = null;
  }

  /// 清除缓存
  void clearCache() {
    _cachedChapterData = null;
  }

  /// 根据搜索结果定位到段落级位置
  ///
  /// 通过遍历章节的 TextContent tags 累计文本偏移，
  /// 将 matchOffset 映射到段落索引和段落内字符偏移。
  /// 返回 SearchPosition，需通过 TextEngine.resolveSearchPosition
  /// 进一步解析为精确的 elementIndex/charIndex。
  ///
  /// 偏移规则与 toPlainText() 严格一致：
  ///   - TextContentTag 贡献 content.length 个字符
  ///   - TextParagraphTag（非 endOfSection）在已有文本后贡献 1 个 '\n'
  ///   - paragraphIndex 计数所有 TextParagraphTag（含 endOfSection），
  ///     与 TextChapterCursor 保持一致
  SearchPosition? findPositionForResult(SearchResult result) {
    final chapters = _plugin.getChapters();
    if (result.chapterIndex >= chapters.length) return null;

    final content = _plugin.getChapterContent(chapters[result.chapterIndex]);
    if (content == null) return null;

    int textOffset = 0;
    int paragraphIndex = -1;
    int paragraphTextStart = 0;
    bool hasText = false; // 等价于 toPlainText() 中 buf.isNotEmpty

    for (final tag in content.tags) {
      if (tag is TextParagraphTag) {
        // 所有 ParagraphTag 都计入 paragraphIndex（与 TextChapterCursor 一致）
        paragraphIndex++;
        if (tag.type != TextParagraphType.endOfSectionParagraph) {
          // 非 endOfSection 段落：在已有文本后插入 '\n' 分隔
          if (hasText) {
            textOffset += 1;
          }
          paragraphTextStart = textOffset;
        }
      } else if (tag is TextContentTag) {
        final tagLen = tag.content.length;
        if (textOffset + tagLen > result.matchOffset) {
          return SearchPosition(
            chapterIndex: result.chapterIndex,
            paragraphIndex: paragraphIndex.clamp(0, 0x7FFFFFFF),
            charOffsetInParagraph: result.matchOffset - paragraphTextStart,
          );
        }
        textOffset += tagLen;
        hasText = true;
      }
    }

    return SearchPosition(
      chapterIndex: result.chapterIndex,
      paragraphIndex: 0,
      charOffsetInParagraph: 0,
    );
  }

  /// 释放资源
  void dispose() {
    _disposed = true;
    _cancelCurrentSearch();
    _cachedChapterData = null;
  }
}
