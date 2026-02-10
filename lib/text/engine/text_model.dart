import '../entity/text_chapter.dart';
import '../entity/text_content.dart';
import '../../parser/format_plugin.dart';
import 'cursor/text_chapter_cursor.dart';

/// 文本数据模型 - 章节加载模块
/// 移植自 Kotlin TextModel
class TextModel {
  final FormatPlugin _plugin;
  late final List<TextChapter> _chapters;

  /// 章节光标 LRU 缓存（最多缓存 5 个）
  final Map<int, TextChapterCursor> _chapterCursorCache = {};
  final List<int> _cacheOrder = [];
  static const int _maxCacheSize = 5;

  TextModel(this._plugin) {
    _chapters = _plugin.getChapters();
  }

  /// 获取语言
  String getLanguage() => _plugin.getLanguage();

  /// 获取章节信息
  TextChapter getChapter(int index) {
    if (index < 0 || index >= _chapters.length) {
      throw RangeError('chapter index $index out of range [0, ${_chapters.length})');
    }
    return _chapters[index];
  }

  /// 获取章节内容
  TextContent? getChapterContent(int index) {
    return _plugin.getChapterContent(getChapter(index));
  }

  /// 获取章节光标（带 LRU 缓存）
  TextChapterCursor getChapterCursor(int index) {
    if (index < 0 || index >= _chapters.length) {
      throw RangeError('chapter index $index out of range [0, ${_chapters.length})');
    }

    var cursor = _chapterCursorCache[index];
    if (cursor != null) {
      // 移到最近使用
      _cacheOrder.remove(index);
      _cacheOrder.add(index);
      return cursor;
    }

    // 缓存淘汰
    if (_cacheOrder.length >= _maxCacheSize) {
      final evicted = _cacheOrder.removeAt(0);
      _chapterCursorCache.remove(evicted);
    }

    cursor = TextChapterCursor(this, index);
    _chapterCursorCache[index] = cursor;
    _cacheOrder.add(index);
    return cursor;
  }

  /// 获取章节总数
  int getChapterCount() => _chapters.length;

  /// 获取章节列表
  List<TextChapter> getChapters() => List.unmodifiable(_chapters);

  /// 清除章节光标缓存（当文本配置变更时调用，确保重新计算元素宽度等）
  void clearCache() {
    _chapterCursorCache.clear();
    _cacheOrder.clear();
  }
}
