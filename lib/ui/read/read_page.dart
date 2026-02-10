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
import 'catalog_drawer.dart';
import 'read_menu.dart';

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

    if (_showMenu) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  void _openCatalog() {
    setState(() => _showMenu = false);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _scaffoldKey.currentState?.openDrawer();
  }

  void _onChapterTap(int index) {
    Navigator.of(context).pop(); // close drawer
    final reader = _readerKey.currentState;
    if (reader == null) return;
    reader.skipChapter(index);
  }

  TextConfig _buildTextConfig() {
    return TextConfig(
      textColor: _isNightMode ? 0xFF999999 : 0xFF333333,
      bgColor: _isNightMode ? 0xFF1A1A1A : 0xFFF5F0E8,
      marginLeft: _marginHorizontal,
      marginRight: _marginHorizontal,
      marginTop: _marginVertical,
      marginBottom: _marginVertical,
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

    final bgColor = Color(_textConfig.bgColor);
    final textColor = Color(_textConfig.textColor);

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
          // 阅读器主体
          Column(
            children: [
              // Header
              Container(
                color: bgColor,
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 4,
                  left: 16,
                  right: 16,
                  bottom: 4,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _chapterTitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: textColor.withValues(alpha: 0.5),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              // Reader
              Expanded(
                child: TextReaderWidget(
                  key: _readerKey,
                  textModel: _model!,
                  textConfig: _textConfig,
                  animType: _animType,
                  onPageChanged: _onPageChanged,
                  onMenuTap: _toggleMenu,
                ),
              ),
              // Footer
              Container(
                color: bgColor,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    Text(
                      _pageCount > 0
                          ? '${_pageIndex + 1}/$_pageCount'
                          : '',
                      style: TextStyle(
                        fontSize: 11,
                        color: textColor.withValues(alpha: 0.4),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _timeStr,
                      style: TextStyle(
                        fontSize: 11,
                        color: textColor.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
