import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../core/book_entity.dart';
import '../../core/book_type.dart';
import '../../data/book_repository.dart';
import '../../parser/epub/epub_plugin.dart';
import '../../parser/format_plugin.dart';
import '../../parser/txt/txt_plugin.dart';
import '../../text/config/text_config.dart';
import '../../text/engine/text_model.dart';
import '../../text/style/tree_text_style.dart';
import '../../text/engine/text_page_controller.dart';
import '../../text/entity/text_chapter.dart';
import '../../text/entity/text_position.dart';
import '../../widget/page_enum.dart';
import '../../widget/text_reader_widget.dart';
import '../../text/search/text_search_engine.dart';
import 'catalog_drawer.dart';
import 'read_menu.dart';
import 'search_page.dart';

/// 阅读页面
class ReadPage extends StatefulWidget {
  final BookEntity book;

  const ReadPage({super.key, required this.book});

  @override
  State<ReadPage> createState() => _ReadPageState();
}

class _ReadPageState extends State<ReadPage> {
  final _readerKey = GlobalKey<TextReaderWidgetState>();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  FormatPlugin? _plugin;
  TextModel? _model;
  TextSearchEngine? _searchEngine;
  List<TextChapter> _chapters = [];

  bool _isLoading = true;
  String? _errorMsg;

  // 菜单状态
  bool _showMenu = false;
  bool _showSetting = false;
  bool _isNightMode = false;

  // 页面信息
  String _chapterTitle = '';
  int _currentChapterIndex = 0;
  int _pageIndex = 0;
  int _pageCount = 0;

  // 配置
  int _fontSize = 18;
  int _lineSpacePercent = 150;
  double _letterSpacing = 0.5;
  int _marginHorizontal = 24;
  int _marginVertical = 16;
  PageAnimType _animType = PageAnimType.simulation;
  late TextConfig _textConfig;

  /// 安全区内边距（刘海/状态栏）
  double _safePaddingTop = 0;
  bool _safePaddingInitialized = false;

  /// header/footer 信息区域高度（固定值）
  static const int _pageInfoHeight = 24;

  // 时间刷新定时器
  Timer? _clockTimer;
  String _timeStr = '';

  @override
  void initState() {
    super.initState();
    _textConfig = _buildTextConfig();
    _updateTime();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _updateTime();
    });
    // 全屏沉浸模式
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _loadBook();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _saveProgress();
    _searchEngine?.dispose();
    _plugin?.release();
    // 退出全屏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _updateTime() {
    final now = DateTime.now();
    setState(() {
      _timeStr =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    });
  }

  Future<void> _loadBook() async {
    try {
      // 根据文件扩展名检测类型（比持久化的 type 更可靠）
      final ext = p.extension(widget.book.url).toLowerCase();
      final bookType = BookType.fromExtension(ext) ?? widget.book.type;

      switch (bookType) {
        case BookType.txt:
          _plugin = TxtPlugin();
          break;
        case BookType.epub:
          _plugin = EpubPlugin();
          break;
      }

      await _plugin!.openBook(widget.book.url);
      _model = TextModel(_plugin!);
      _chapters = _model!.getChapters();

      // 初始化搜索引擎并预加载章节文本
      _searchEngine = TextSearchEngine(_plugin!);
      _searchEngine!.preloadChapterTexts();

      setState(() {
        _isLoading = false;
      });

      // 恢复阅读进度（延迟到 reader 初始化后）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restoreProgress();
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMsg = '加载失败: $e';
      });
    }
  }

  void _restoreProgress() {
    final reader = _readerKey.currentState;
    if (reader == null || !reader.isInitialized) {
      // 延迟重试
      Future.delayed(const Duration(milliseconds: 200), _restoreProgress);
      return;
    }

    final chapterIndex = widget.book.lastChapterIndex ?? 0;
    final paragraphIndex = widget.book.lastParagraphIndex;
    final elementIndex = widget.book.lastElementIndex;
    final charIndex = widget.book.lastCharIndex;

    if (paragraphIndex != null && elementIndex != null && charIndex != null) {
      // 精确文本位置恢复（跨配置变更后仍准确）
      reader.skipToTextPosition(TextFixedPosition(
        chapterIndex: chapterIndex,
        paragraphIndex: paragraphIndex,
        elementIndex: elementIndex,
        charIndex: charIndex,
      ));
    } else if (chapterIndex > 0) {
      // 仅有章节信息，跳转到章节首页
      reader.skipChapter(chapterIndex);
    }
  }

  void _saveProgress() {
    final reader = _readerKey.currentState;
    if (reader == null) return;
    final textPos = reader.getTextPosition();
    if (textPos != null) {
      BookRepository.instance.updateReadProgress(
        widget.book.id,
        chapterIndex: textPos.chapterIndex,
        paragraphIndex: textPos.paragraphIndex,
        elementIndex: textPos.elementIndex,
        charIndex: textPos.charIndex,
      );
    }
  }

  void _onPageChanged(PagePosition pos, PageProgress progress) {
    final prevChapter = _currentChapterIndex;
    setState(() {
      _currentChapterIndex = pos.chapterIndex;
      _pageIndex = progress.pageIndex;
      _pageCount = progress.pageCount;
      if (pos.chapterIndex < _chapters.length) {
        _chapterTitle = _chapters[pos.chapterIndex].title;
      }
    });
    // 切换章节时自动保存进度
    if (pos.chapterIndex != prevChapter) {
      _saveProgress();
    }
  }

  void _saveProgressWithFeedback() {
    _saveProgress();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已保存阅读进度'),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
    // 关闭菜单
    _toggleMenu();
  }

  void _toggleMenu() {
    setState(() {
      if (_showSetting) {
        _showSetting = false;
        return;
      }
      _showMenu = !_showMenu;
      if (!_showMenu) _showSetting = false;
    });
  }

  void _openCatalog() {
    setState(() => _showMenu = false);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _scaffoldKey.currentState?.openDrawer();
  }

  void _openSearch() async {
    setState(() => _showMenu = false);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    if (_searchEngine == null) return;

    final result = await Navigator.of(context).push<SearchResult>(
      MaterialPageRoute(
        builder: (_) => SearchPage(searchEngine: _searchEngine!),
      ),
    );

    // 先恢复沉浸模式并等待一帧，让 MediaQuery.padding.top 稳定后再跳转，
    // 避免异步 safeTop 变化触发 updateTextConfig 导致的二次跳转。
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // 等待一帧让布局完成
    if (mounted) {
      await WidgetsBinding.instance.endOfFrame;
    }

    if (result != null && mounted) {
      // 定位到搜索结果所在段落并跳转 + 高亮
      final reader = _readerKey.currentState;
      if (reader != null) {
        final searchPos = _searchEngine!.findPositionForResult(result);
        if (searchPos != null) {
          final position = reader.engine.resolveSearchPosition(searchPos);
          reader.setHighlight(result.keyword, position);
        } else {
          reader.skipChapter(result.chapterIndex);
        }
      }
    }
  }

  void _onChapterTap(int index) {
    Navigator.of(context).pop(); // close drawer
    final reader = _readerKey.currentState;
    if (reader == null) return;
    reader.skipChapter(index);
  }

  /// 阅读器区域点击：中间 1/3 区域切换菜单
  void _onReaderTap(TapUpDetails details) {
    final width = context.size?.width ?? 0;
    final x = details.localPosition.dx;
    if (x > width / 3 && x < width * 2 / 3) {
      _toggleMenu();
    }
  }

  TextConfig _buildTextConfig() {
    // marginTop 需要包含: safe area + header 信息区 + 用户边距
    // marginBottom 需要包含: footer 信息区 + 用户边距
    final safeTop = _safePaddingInitialized ? _safePaddingTop.toInt() : 0;
    return TextConfig(
      textColor: _isNightMode ? 0xFF999999 : 0xFF333333,
      bgColor: _isNightMode ? 0xFF1A1A1A : 0xFFF5F0E8,
      marginLeft: _marginHorizontal,
      marginRight: _marginHorizontal,
      marginTop: safeTop + _pageInfoHeight + _marginVertical,
      marginBottom: _pageInfoHeight + _marginVertical,
      baseTextStyle: TreeTextStyle(
        fontSize: _fontSize,
        lineSpacePercent: _lineSpacePercent,
        letterSpacing: _letterSpacing,
      ),
    );
  }

  void _toggleNightMode() {
    setState(() {
      _isNightMode = !_isNightMode;
      _textConfig = _buildTextConfig();
    });
    _readerKey.currentState?.updateTextConfig(_textConfig);
  }

  void _onFontSizeChanged(int newSize) {
    setState(() {
      _fontSize = newSize;
      _textConfig = _buildTextConfig();
    });
    _readerKey.currentState?.updateTextConfig(_textConfig);
  }

  void _onLineSpaceChanged(int value) {
    setState(() {
      _lineSpacePercent = value;
      _textConfig = _buildTextConfig();
    });
    _readerKey.currentState?.updateTextConfig(_textConfig);
  }

  void _onLetterSpacingChanged(double value) {
    setState(() {
      _letterSpacing = value;
      _textConfig = _buildTextConfig();
    });
    _readerKey.currentState?.updateTextConfig(_textConfig);
  }

  void _onMarginHorizontalChanged(int value) {
    setState(() {
      _marginHorizontal = value;
      _textConfig = _buildTextConfig();
    });
    _readerKey.currentState?.updateTextConfig(_textConfig);
  }

  void _onMarginVerticalChanged(int value) {
    setState(() {
      _marginVertical = value;
      _textConfig = _buildTextConfig();
    });
    _readerKey.currentState?.updateTextConfig(_textConfig);
  }

  void _onAnimTypeChanged(PageAnimType type) {
    setState(() => _animType = type);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F0E8),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在加载书籍...', style: TextStyle(color: Color(0xFF666666))),
            ],
          ),
        ),
      );
    }

    if (_errorMsg != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('加载失败')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(_errorMsg!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('返回'),
              ),
            ],
          ),
        ),
      );
    }

    // 计算 safe area 并在首次/变化时更新 TextConfig
    final safeTop = MediaQuery.of(context).padding.top;
    if (!_safePaddingInitialized || _safePaddingTop != safeTop) {
      _safePaddingTop = safeTop;
      _safePaddingInitialized = true;
      // 延迟重建 config，避免在 build 中直接 setState
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _textConfig = _buildTextConfig());
          _readerKey.currentState?.updateTextConfig(_textConfig);
        }
      });
    }

    final bgColor = Color(_textConfig.bgColor);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: bgColor,
      drawer: CatalogDrawer(
        bookTitle: widget.book.title,
        chapters: _chapters,
        currentChapterIndex: _currentChapterIndex,
        onChapterTap: _onChapterTap,
      ),
      // 禁止手势打开 drawer（仅通过菜单按钮打开）
      drawerEnableOpenDragGesture: false,
      body: Stack(
        children: [
          // 阅读器主体（全屏，header/footer 绘制在 Canvas 的 margin 区域）
          Positioned.fill(
            child: TextReaderWidget(
              key: _readerKey,
              textModel: _model!,
              textConfig: _textConfig,
              animType: _animType,
              onPageChanged: _onPageChanged,
              headerText: _chapterTitle,
              footerLeftText: _pageCount > 0
                  ? '${_pageIndex + 1}/$_pageCount'
                  : null,
              footerRightText: _timeStr,
              safePaddingTop: _safePaddingTop,
            ),
          ),

          // 居中点击检测层（与 TextReaderWidget 的 pan 手势通过手势竞技场自动区分）
          if (!_showMenu)
            Positioned.fill(
              child: GestureDetector(
                onTapUp: _onReaderTap,
                behavior: HitTestBehavior.translucent,
              ),
            ),

          // 菜单遮罩 + 菜单
          if (_showMenu) ...[
            // 点击遮罩关闭菜单
            Positioned.fill(
              child: GestureDetector(
                onTap: _toggleMenu,
                behavior: HitTestBehavior.translucent,
                child: Container(color: Colors.transparent),
              ),
            ),
            // 顶部菜单
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                color: const Color(0xCC333333),
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top,
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon:
                          const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () {
                        _saveProgress();
                        Navigator.of(context).pop();
                      },
                    ),
                    Expanded(
                      child: Text(
                        widget.book.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
            ),
            // 底部菜单或设置面板
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _showSetting
                  ? ReadSettingPanel(
                      fontSize: _fontSize,
                      lineSpacePercent: _lineSpacePercent,
                      letterSpacing: _letterSpacing,
                      marginHorizontal: _marginHorizontal,
                      marginVertical: _marginVertical,
                      animType: _animType,
                      onFontSizeChanged: _onFontSizeChanged,
                      onLineSpaceChanged: _onLineSpaceChanged,
                      onLetterSpacingChanged: _onLetterSpacingChanged,
                      onMarginHorizontalChanged: _onMarginHorizontalChanged,
                      onMarginVerticalChanged: _onMarginVerticalChanged,
                      onAnimTypeChanged: _onAnimTypeChanged,
                    )
                  : ReadBottomMenu(
                      isNightMode: _isNightMode,
                      onCatalogTap: _openCatalog,
                      onSearchTap: _openSearch,
                      onBookmarkTap: _saveProgressWithFeedback,
                      onNightModeTap: _toggleNightMode,
                      onSettingTap: () {
                        setState(() => _showSetting = true);
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
