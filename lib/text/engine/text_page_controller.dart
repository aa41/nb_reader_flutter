import 'dart:math';

import '../entity/text_page.dart';
import '../entity/text_position.dart';
import '../../widget/page_enum.dart';
import 'cursor/text_word_cursor.dart';
import 'text_model.dart';

/// 查找页面结尾光标的回调
typedef FindPageEndCursorFn = TextWordCursor Function(
    int width, int height, TextWordCursor startCursor);

/// 页面控制器 - 管理页面缓存和翻页
/// 移植自 Kotlin TextPageController
class TextPageController {
  final TextModel _textModel;
  final FindPageEndCursorFn _findPageEndCursor;

  int pageWidth = 0;
  int pageHeight = 0;

  _ChapterWrapper? _prevChapter;
  _ChapterWrapper? _curChapter;
  _ChapterWrapper? _nextChapter;
  _PageWrapper? _curPage;

  TextPageController(this._textModel, this._findPageEndCursor);

  /// 设置视口
  void setViewPort(int width, int height) {
    if (pageWidth == width && pageHeight == height) return;
    pageWidth = width;
    pageHeight = height;

    if (_curPage != null) {
      final pos = TextFixedPosition.fromPosition(_curPage!.textPage.startWordCursor);
      reset();
      skipPageByPosition(pos);
    }
  }

  /// 通过 TextPosition 跳转页面
  void skipPageByPosition(TextPosition position) {
    assert(pageWidth > 0 && pageHeight > 0);

    final pageWrapper = _findPageByPosition(position);
    if (pageWrapper == null) {
      reset();
      _curChapter = _loadChapterPages(position.chapterIndex);
      _curPage = _findPageByPosition(position);
    } else {
      _curPage = pageWrapper;
      _syncChapterPointers(pageWrapper);
    }
  }

  /// 通过 PagePosition 跳转页面
  void skipPageByPagePosition(PagePosition position) {
    assert(pageWidth > 0 && pageHeight > 0);

    final wrapper = _findChapterWrapper(position.chapterIndex);
    if (wrapper == null) {
      reset();
      _curChapter = _loadChapterPages(position.chapterIndex);
      final pages = _curChapter!.pages;
      if (position.pageIndex < pages.length) {
        _curPage = _PageWrapper(_curChapter!, position.pageIndex, pages[position.pageIndex]);
      }
    } else {
      final pages = wrapper.pages;
      if (position.pageIndex < pages.length) {
        _curPage = _PageWrapper(wrapper, position.pageIndex, pages[position.pageIndex]);
        _syncChapterPointers(_curPage!);
      }
    }
  }

  /// 跳转到目标页面后，直接同步章节指针（prev/cur/next）。
  /// 不调用 turnPage，避免 turnPage 内部的 _nextPageWrapper/_prevPageWrapper
  /// 错误地将 _curPage 覆盖为下一页/上一页。
  void _syncChapterPointers(_PageWrapper pageWrapper) {
    if (pageWrapper.chapterWrapper == _curChapter) return;
    if (pageWrapper.chapterWrapper == _prevChapter) {
      _nextChapter = _curChapter;
      _curChapter = _prevChapter;
      _prevChapter = null;
    } else if (pageWrapper.chapterWrapper == _nextChapter) {
      _prevChapter = _curChapter;
      _curChapter = _nextChapter;
      _nextChapter = null;
    }
  }

  // === 页面查询 ===

  TextPage? getCurrentPage() => _curPage?.textPage;
  int? getCurrentPageIndex() => _curPage?.pageIndex;
  int getCurrentPageCount() => _curChapter?.pages.length ?? 0;

  bool hasPage(PageType type) {
    switch (type) {
      case PageType.previous:
        return _hasPrevPage();
      case PageType.next:
        return _hasNextPage();
      case PageType.current:
        return _curPage != null;
    }
  }

  TextPage? prevPage() => _prevPageWrapper()?.textPage;
  TextPage? nextPage() => _nextPageWrapper()?.textPage;

  PagePosition? getPagePosition(PageType type) {
    final pw = _getPageWrapper(type);
    if (pw == null) return null;
    return PagePosition(pw.chapterWrapper.chapterIndex, pw.pageIndex);
  }

  PageProgress? getPageProgress(PageType type) {
    final pw = _getPageWrapper(type);
    if (pw == null) return null;
    return PageProgress(pw.pageIndex, pw.chapterWrapper.pages.length, 0);
  }

  int getPageCount(PageType type) {
    switch (type) {
      case PageType.previous:
        return _prevChapter?.pages.length ?? 0;
      case PageType.current:
        return _curChapter?.pages.length ?? 0;
      case PageType.next:
        return _nextChapter?.pages.length ?? 0;
    }
  }

  // === 翻页 ===

  void turnPage(PageType type) {
    if (_curPage == null) return;

    final newPage = switch (type) {
      PageType.previous => _prevPageWrapper(),
      PageType.next => _nextPageWrapper(),
      PageType.current => _curPage,
    };

    if (newPage == null) return;

    var isTurnChapter = false;
    final oldPage = _curPage!;

    if (oldPage.chapterWrapper.chapterIndex != newPage.chapterWrapper.chapterIndex) {
      isTurnChapter = true;
    }

    _curPage = newPage;

    if (isTurnChapter) {
      _turnChapter(type);
    }
  }

  // === 内部方法 ===

  bool _hasPrevPage() {
    if (_curPage == null) return false;
    return !_curPage!.textPage.startWordCursor.isStartOfText();
  }

  bool _hasNextPage() {
    if (_curPage == null) return false;
    return !_curPage!.textPage.endWordCursor.isEndOfText();
  }

  _PageWrapper? _getPageWrapper(PageType type) {
    return switch (type) {
      PageType.previous => _prevPageWrapper(),
      PageType.current => _curPage,
      PageType.next => _nextPageWrapper(),
    };
  }

  _PageWrapper? _prevPageWrapper() {
    if (!_hasPrevPage()) return null;
    if (_curPage!.pageIndex > 0) {
      return _getPageFromType(PageType.current, _curPage!.pageIndex - 1);
    }
    return _getPageFromType(PageType.previous, 0x7FFFFFFF); // MAX_VALUE
  }

  _PageWrapper? _nextPageWrapper() {
    if (!_hasNextPage()) return null;
    if (_curPage!.pageIndex < (_curChapter?.pages.length ?? 0) - 1) {
      return _getPageFromType(PageType.current, _curPage!.pageIndex + 1);
    }
    return _getPageFromType(PageType.next, 0);
  }

  _PageWrapper _getPageFromType(PageType type, int pageIndex) {
    final curWrapper = _curPage!.chapterWrapper;

    final chapterWrapper = switch (type) {
      PageType.previous => () {
          _prevChapter ??= _loadChapterPages(curWrapper.chapterIndex - 1);
          return _prevChapter!;
        }(),
      PageType.current => curWrapper,
      PageType.next => () {
          _nextChapter ??= _loadChapterPages(curWrapper.chapterIndex + 1);
          return _nextChapter!;
        }(),
    };

    final pages = chapterWrapper.pages;
    final idx = min(pages.length - 1, pageIndex);
    return _PageWrapper(chapterWrapper, idx, pages[idx]);
  }

  _ChapterWrapper? _findChapterWrapper(int chapterIndex) {
    for (final w in [_prevChapter, _curChapter, _nextChapter]) {
      if (w != null && w.chapterIndex == chapterIndex) return w;
    }
    return null;
  }

  _PageWrapper? _findPageByPosition(TextPosition position) {
    final wrapper = _findChapterWrapper(position.chapterIndex);
    if (wrapper == null) return null;

    for (int i = 0; i < wrapper.pages.length; i++) {
      if (wrapper.pages[i].endWordCursor > position) {
        return _PageWrapper(wrapper, i, wrapper.pages[i]);
      }
    }
    return null;
  }

  /// 加载章节页面
  _ChapterWrapper _loadChapterPages(int chapterIndex) {
    assert(chapterIndex >= 0 && chapterIndex < _textModel.getChapterCount());

    final chapterCursor = _textModel.getChapterCursor(chapterIndex);
    if (chapterCursor.getParagraphCount() == 0) {
      return _ChapterWrapper(chapterIndex, []);
    }

    final curWordCursor = TextWordCursor(chapterCursor.getParagraphCursor(0));
    final endWordCursor = TextWordCursor(
        chapterCursor.getParagraphCursor(chapterCursor.getParagraphCount() - 1));
    endWordCursor.moveToParagraphEnd();

    final pages = <TextPage>[];
    final pageStartCursor = TextWordCursor.copy(curWordCursor);

    while (curWordCursor < endWordCursor) {
      final pageEndCursor = _findPageEndCursor(pageWidth, pageHeight, curWordCursor);
      pages.add(TextPage(pageStartCursor, pageEndCursor));
      curWordCursor.updateCursor(pageEndCursor);
      pageStartCursor.updateCursor(pageEndCursor);
    }

    return _ChapterWrapper(chapterIndex, pages);
  }

  void _turnChapter(PageType type) {
    switch (type) {
      case PageType.previous:
        _nextChapter = _curChapter;
        _curChapter = _prevChapter;
        _prevChapter = null;
        break;
      case PageType.next:
        _prevChapter = _curChapter;
        _curChapter = _nextChapter;
        _nextChapter = null;
        break;
      case PageType.current:
        break;
    }
  }

  void reset() {
    _prevChapter = null;
    _curChapter = null;
    _nextChapter = null;
    _curPage = null;
  }
}

/// 章节包装器
class _ChapterWrapper {
  final int chapterIndex;
  final List<TextPage> pages;

  _ChapterWrapper(this.chapterIndex, this.pages);
}

/// 页面包装器
class _PageWrapper {
  final _ChapterWrapper chapterWrapper;
  final int pageIndex;
  final TextPage textPage;

  _PageWrapper(this.chapterWrapper, this.pageIndex, this.textPage);
}

/// 页面定位
class PagePosition {
  final int chapterIndex;
  final int pageIndex;

  PagePosition(this.chapterIndex, this.pageIndex);

  @override
  String toString() => 'PagePosition(ch=$chapterIndex, page=$pageIndex)';
}

/// 页面进度
class PageProgress {
  final int pageIndex;
  final int pageCount;
  final double totalProgress;

  PageProgress(this.pageIndex, this.pageCount, this.totalProgress);

  @override
  String toString() => 'PageProgress($pageIndex/$pageCount)';
}
