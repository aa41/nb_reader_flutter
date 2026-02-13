import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../core/book_entity.dart';
import '../../core/book_type.dart';
import '../../data/annotation_repository.dart';
import '../../data/book_repository.dart';
import '../../parser/epub/epub_plugin.dart';
import '../../parser/format_plugin.dart';
import '../../parser/markdown/markdown_plugin.dart';
import '../../parser/txt/txt_plugin.dart';
import '../../text/annotation/text_annotation.dart';
import '../../text/config/text_config.dart';
import '../../text/engine/text_model.dart';
import '../../text/style/tree_text_style.dart';
import '../../text/engine/text_page_controller.dart';
import '../../text/entity/text_chapter.dart';
import '../../text/entity/text_position.dart';
import '../../widget/page_enum.dart';
import '../../widget/text_reader_widget.dart';
import '../../text/search/text_search_engine.dart';
import 'annotation_widgets.dart';
import 'catalog_drawer.dart';
import 'read_menu.dart';
import 'search_page.dart';

/// 阅读页面
class ReadPage extends StatefulWidget {
  final BookEntity book;

  /// 外部自定义"想法"展示/编辑回调：
  /// - 如果返回非空字符串，则视为用户保存了新的想法内容（用于创建/更新）
  /// - 返回 null 视为取消/不修改
  final Future<String?> Function(BuildContext context, TextAnnotation note)? onShowNote;

  /// 自定义工具选项（显示在"写想法"后面）
  final List<AnnotationToolOption> extraToolOptions;

  const ReadPage({
    super.key,
    required this.book,
    this.onShowNote,
    this.extraToolOptions = const [],
  });

  @override
  State<ReadPage> createState() => _ReadPageState();
}

enum _DragHandle {
  start,
  end,
}

enum _NoteAction {
  edit,
  delete,
}

class _ReadPageState extends State<ReadPage> {
  final _readerKey = GlobalKey<TextReaderWidgetState>();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _readerBoxKey = GlobalKey();

  // === 标注/选择态 ===

  List<TextAnnotation> _annotations = [];
  bool _annotationsLoaded = false;

  TextFixedPosition? _selStart;
  TextFixedPosition? _selEnd;
  String? _activeAnnotationId;

  bool _showAnnotationBar = false;
  bool _showStylePanel = false;
  TextAnnotationStyleType _editStyleType = TextAnnotationStyleType.background;
  int _editColor = kAnnotationColors.last;

  _DragHandle? _draggingHandle;
  Offset? _lastDragGlobalPos;

  /// 选择工具条定位锚点（reader 坐标系）
  Offset? _selectionAnchorLocal;

  Timer? _autoTurnTimer;
  PageType? _autoTurnType;

  static const double _autoTurnHotZoneSize = 64;
  static const int _autoTurnIntervalMs = 450;

  bool get _selectionMode => _selStart != null && _selEnd != null;

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
    _autoTurnTimer?.cancel();
    _clockTimer?.cancel();
    _readerKey.currentState?.clearSelectionRange();
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
        case BookType.md:
          _plugin = MarkdownPlugin();
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

      // 加载标注（延迟到 reader 初始化后应用到引擎）
      _loadAnnotations();

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

  Future<void> _loadAnnotations() async {
    try {
      final list = await AnnotationRepository.instance.loadAnnotations(widget.book.id);
      if (!mounted) return;
      setState(() {
        _annotations = list;
        _annotationsLoaded = true;
      });
      _applyAnnotationsToReader();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _annotations = [];
        _annotationsLoaded = true;
      });
      _applyAnnotationsToReader();
    }
  }

  void _applyAnnotationsToReader() {
    if (!mounted) return;
    final reader = _readerKey.currentState;
    if (reader == null || !reader.isInitialized) {
      // 延迟到初始化后再应用
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyAnnotationsToReader();
      });
      return;
    }
    reader.setAnnotations(_annotations);
  }

  void _persistAnnotations() {
    if (!_annotationsLoaded) return;
    unawaited(
      AnnotationRepository.instance.saveAnnotations(widget.book.id, _annotations),
    );
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
    // 打开菜单时，优先退出选择态，避免交互冲突
    if (!_showMenu && _selectionMode) {
      _clearSelection();
    }

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

  // === 标注/选择态辅助方法 ===

  void _setSelectionRange(
    TextFixedPosition start,
    TextFixedPosition end, {
    String? activeAnnotationId,
    bool showStylePanel = false,
  }) {
    final (s, e) = TextAnnotation.normalizeRange(start, end);

    setState(() {
      _selStart = s;
      _selEnd = e;
      _activeAnnotationId = activeAnnotationId;
      _showAnnotationBar = true;
      _showStylePanel = showStylePanel;
    });

    _readerKey.currentState?.setSelectionRange(s, e);
  }

  void _clearSelection() {
    _autoTurnTimer?.cancel();
    _autoTurnTimer = null;
    _autoTurnType = null;
    _draggingHandle = null;
    _lastDragGlobalPos = null;
    _selectionAnchorLocal = null;

    setState(() {
      _selStart = null;
      _selEnd = null;
      _activeAnnotationId = null;
      _showAnnotationBar = false;
      _showStylePanel = false;
    });

    _readerKey.currentState?.clearSelectionRange();
  }

  TextAnnotation? _findAnnotationById(String id) {
    for (final a in _annotations) {
      if (a.id == id) return a;
    }
    return null;
  }

  TextAnnotation? _hitTestAnnotation(TextFixedPosition pos) {
    final hits = <TextAnnotation>[];
    for (final a in _annotations) {
      // 右开区间: [start, end)
      if (pos.compareTo(a.start) >= 0 && pos.compareTo(a.end) < 0) {
        hits.add(a);
      }
    }
    if (hits.isEmpty) return null;

    // 重叠优先级：高亮优先（已确认）
    TextAnnotation? best;
    for (final a in hits) {
      if (a.kind != TextAnnotationKind.highlight) continue;
      if (best == null || a.updatedAt >= best.updatedAt) best = a;
    }
    if (best != null) return best;

    // 其次取想法
    for (final a in hits) {
      if (a.kind != TextAnnotationKind.note) continue;
      if (best == null || a.updatedAt >= best.updatedAt) best = a;
    }
    return best;
  }

  void _upsertAnnotation(TextAnnotation ann, {bool persist = true}) {
    final idx = _annotations.indexWhere((a) => a.id == ann.id);
    setState(() {
      if (idx >= 0) {
        _annotations[idx] = ann.normalized();
      } else {
        _annotations.add(ann.normalized());
      }
    });

    _readerKey.currentState?.setAnnotations(_annotations);
    if (persist) _persistAnnotations();
  }

  void _deleteAnnotation(String id, {bool persist = true}) {
    setState(() {
      _annotations.removeWhere((a) => a.id == id);
    });

    _readerKey.currentState?.setAnnotations(_annotations);
    if (persist) _persistAnnotations();
  }

  // === 拖拽选择（手柄 + 自动翻页） ===

  void _onHandlePanStart(_DragHandle handle, DragStartDetails details) {
    _draggingHandle = handle;
    _lastDragGlobalPos = details.globalPosition;
  }

  void _onHandlePanUpdate(DragUpdateDetails details) {
    _lastDragGlobalPos = details.globalPosition;
    _updateSelectionByGlobal(details.globalPosition);
  }

  void _onHandlePanEnd(DragEndDetails details) {
    _stopAutoTurn();

    final reader = _readerKey.currentState;
    final activeId = _activeAnnotationId;
    final s = _selStart;
    final e = _selEnd;

    _draggingHandle = null;
    _lastDragGlobalPos = null;

    // 若正在编辑已有高亮，拖拽结束后持久化范围变化
    if (reader != null && activeId != null && s != null && e != null) {
      final ann = _findAnnotationById(activeId);
      if (ann != null && ann.kind == TextAnnotationKind.highlight) {
        final now = DateTime.now().millisecondsSinceEpoch;
        _upsertAnnotation(
          ann.copyWith(start: s, end: e, updatedAt: now),
          persist: true,
        );
      }
    }
  }

  void _updateSelectionByGlobal(Offset globalPos) {
    final reader = _readerKey.currentState;
    if (reader == null || !_selectionMode) return;

    final ctx = _readerBoxKey.currentContext;
    final ro = ctx?.findRenderObject();
    if (ro is! RenderBox) return;

    final local = ro.globalToLocal(globalPos);
    final size = ro.size;

    // 更新自动翻页状态（不要求命中到文字）
    _updateAutoTurn(local, size);

    final handle = _draggingHandle;
    if (handle == null) return;

    final pos = reader.engine.findTextPosition(local.dx, local.dy);
    if (pos == null) return;

    var s = _selStart!;
    var e = _selEnd!;

    if (handle == _DragHandle.start) {
      s = pos;
    } else {
      e = pos;
    }

    // 交叉时交换起止，并切换当前拖拽手柄
    if (s.compareTo(e) > 0) {
      final tmp = s;
      s = e;
      e = tmp;
      _draggingHandle = handle == _DragHandle.start ? _DragHandle.end : _DragHandle.start;
    }

    setState(() {
      _selStart = s;
      _selEnd = e;
      _selectionAnchorLocal = local;
      _showAnnotationBar = true;
    });

    reader.setSelectionRange(s, e);
  }

  void _updateAutoTurn(Offset localPos, Size size) {
    PageType? desired;

    // 左上角 → 上一页
    if (localPos.dx <= _autoTurnHotZoneSize &&
        localPos.dy <= _autoTurnHotZoneSize) {
      desired = PageType.previous;
    }

    // 右下角底部 → 下一页
    if (localPos.dx >= size.width - _autoTurnHotZoneSize &&
        localPos.dy >= size.height - _autoTurnHotZoneSize) {
      desired = PageType.next;
    }

    if (desired == _autoTurnType) return;

    _stopAutoTurn();
    if (desired == null) return;

    _autoTurnType = desired;
    _autoTurnTimer = Timer.periodic(
      const Duration(milliseconds: _autoTurnIntervalMs),
      (_) => _tickAutoTurn(),
    );

    // 立即触发一次，提升响应
    _tickAutoTurn();
  }

  void _stopAutoTurn() {
    _autoTurnTimer?.cancel();
    _autoTurnTimer = null;
    _autoTurnType = null;
  }

  void _tickAutoTurn() {
    final reader = _readerKey.currentState;
    final type = _autoTurnType;
    final gp = _lastDragGlobalPos;

    if (reader == null || type == null || gp == null || _draggingHandle == null) {
      _stopAutoTurn();
      return;
    }

    if (type == PageType.next && !reader.hasNextPage()) {
      _stopAutoTurn();
      return;
    }
    if (type == PageType.previous && !reader.hasPrevPage()) {
      _stopAutoTurn();
      return;
    }

    // 直接翻页（无动画），并在下一帧根据当前拖拽坐标继续更新 selection
    reader.turnPageDirect(type);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final last = _lastDragGlobalPos;
      if (last == null) return;
      _updateSelectionByGlobal(last);
    });
  }

  String _newAnnotationId(String prefix) {
    final t = DateTime.now().microsecondsSinceEpoch;
    final r = Random().nextInt(1 << 32);
    return '${prefix}_${t}_$r';
  }

  Future<void> _copySelection() async {
    final reader = _readerKey.currentState;
    final s = _selStart;
    final e = _selEnd;
    if (reader == null || s == null || e == null) return;

    final text = reader.engine.extractText(s, e);
    if (text.isEmpty) return;

    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制'),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _applyHighlight({
    TextAnnotationStyleType? type,
    int? color,
    bool showStylePanel = true,
  }) {
    final s = _selStart;
    final e = _selEnd;
    if (s == null || e == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final style = TextAnnotationStyle(
      type: type ?? _editStyleType,
      color: color ?? _editColor,
    );

    final activeId = _activeAnnotationId;
    final active = activeId != null ? _findAnnotationById(activeId) : null;

    final TextAnnotation ann;
    if (active != null && active.kind == TextAnnotationKind.highlight) {
      ann = active.copyWith(
        start: s,
        end: e,
        style: style,
        updatedAt: now,
      );
    } else {
      ann = TextAnnotation(
        id: _newAnnotationId('hl'),
        kind: TextAnnotationKind.highlight,
        start: s,
        end: e,
        style: style,
        createdAt: now,
        updatedAt: now,
      );
    }

    _upsertAnnotation(ann, persist: true);
    setState(() {
      _activeAnnotationId = ann.id;
      _showAnnotationBar = true;
      _showStylePanel = showStylePanel;
    });
  }

  void _deleteActiveHighlight() {
    final id = _activeAnnotationId;
    if (id == null) return;
    final ann = _findAnnotationById(id);
    if (ann == null || ann.kind != TextAnnotationKind.highlight) return;

    _deleteAnnotation(id, persist: true);
    setState(() {
      _activeAnnotationId = null;
      _showStylePanel = false;
    });
  }

  Future<void> _createNoteForSelection() async {
    final reader = _readerKey.currentState;
    final s = _selStart;
    final e = _selEnd;
    if (reader == null || s == null || e == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final draft = TextAnnotation(
      id: 'draft',
      kind: TextAnnotationKind.note,
      start: s,
      end: e,
      style: TextAnnotationStyle(
        type: TextAnnotationStyleType.dashedUnderline,
        color: _editColor,
      ),
      noteText: '',
      createdAt: now,
      updatedAt: now,
    );

    final selectedText = reader.engine.extractText(s, e);
    final text = await reader.showNoteBottomSheet(
      note: draft,
      selectedText: selectedText,
      isEdit: false,
    );

    if (!mounted) return;
    if (text == null) return;
    if (text.trim().isEmpty) return;

    final ann = TextAnnotation(
      id: _newAnnotationId('note'),
      kind: TextAnnotationKind.note,
      start: s,
      end: e,
      style: draft.style,
      noteText: text,
      createdAt: now,
      updatedAt: now,
    );

    _upsertAnnotation(ann, persist: true);
    _clearSelection();
  }

  Future<void> _openNote(TextAnnotation note) async {
    final reader = _readerKey.currentState;
    if (reader == null) return;

    final selectedText = reader.engine.extractText(note.start, note.end);

    // 外部自定义想法 BottomSheet：由外部决定展示/编辑逻辑
    if (reader.widget.onShowNoteBottomSheet != null) {
      final text = await reader.showNoteBottomSheet(
        note: note,
        selectedText: selectedText,
        isEdit: true,
      );
      if (!mounted) return;
      if (text == null) return;

      if (text.trim().isEmpty) {
        _deleteAnnotation(note.id, persist: true);
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      _upsertAnnotation(
        note.copyWith(noteText: text, updatedAt: now),
        persist: true,
      );
      return;
    }

    // 默认行为：先展示内容再编辑
    final action = await _showNoteViewSheet(note);
    if (!mounted || action == null) return;

    switch (action) {
      case _NoteAction.delete:
        _deleteAnnotation(note.id, persist: true);
        break;
      case _NoteAction.edit:
        final text = await reader.showNoteBottomSheet(
          note: note,
          selectedText: selectedText,
          isEdit: true,
        );
        if (!mounted || text == null) return;

        if (text.trim().isEmpty) {
          _deleteAnnotation(note.id, persist: true);
          return;
        }

        final now = DateTime.now().millisecondsSinceEpoch;
        _upsertAnnotation(
          note.copyWith(noteText: text, updatedAt: now),
          persist: true,
        );
        break;
    }
  }

  Future<_NoteAction?> _showNoteViewSheet(TextAnnotation note) {
    return showModalBottomSheet<_NoteAction>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final maxH = MediaQuery.of(ctx).size.height * 0.6;
        return SafeArea(
          top: false,
          child: Container(
            constraints: BoxConstraints(maxHeight: maxH),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text(
                      '想法',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: Text(
                      note.noteText ?? '',
                      style: const TextStyle(fontSize: 15, height: 1.4),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(_NoteAction.delete),
                        child: const Text('删除'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(ctx).pop(_NoteAction.edit),
                        child: const Text('编辑'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Offset _getSelectionAnchor(Size size) {
    final a = _selectionAnchorLocal;
    if (a != null) return a;

    final reader = _readerKey.currentState;
    final s = _selStart;
    final e = _selEnd;
    if (reader != null && s != null && e != null) {
      final so = reader.engine.getOffsetForTextPosition(s);
      final eo = reader.engine.getOffsetForTextPosition(e);
      if (so != null && eo != null) {
        return Offset((so.dx + eo.dx) / 2, min(so.dy, eo.dy));
      }
      if (so != null) return so;
      if (eo != null) return eo;
    }

    return Offset(size.width / 2, size.height / 2);
  }

  Offset _computeFloatingTopLeft({
    required Size size,
    required Offset anchor,
    required double approxWidth,
    required double approxHeight,
    required bool preferAbove,
  }) {
    final safeTop = _safePaddingTop;
    final width = min(approxWidth, max(0.0, size.width - 16));
    final height = approxHeight;

    final maxLeft = max(8.0, size.width - 8.0 - width);
    final left = (anchor.dx - width / 2).clamp(8.0, maxLeft).toDouble();

    double top = preferAbove ? (anchor.dy - height - 12) : (anchor.dy + 12);
    if (top < safeTop + 8) top = anchor.dy + 12;

    final maxTop = max(safeTop + 8.0, size.height - 8.0 - height);
    top = top.clamp(safeTop + 8.0, maxTop).toDouble();

    return Offset(left, top);
  }

  List<Widget> _buildAnnotationOverlays(BuildContext context) {
    if (!_selectionMode || _showMenu) return const [];

    final reader = _readerKey.currentState;
    final s = _selStart;
    final e = _selEnd;
    if (reader == null || s == null || e == null) return const [];

    final size = MediaQuery.of(context).size;
    final anchor = _getSelectionAnchor(size);

    const toolbarH = 46.0;
    final toolbarW = size.width * 2 / 3;
    const panelH = 46.0;

    final toolbarPos = _computeFloatingTopLeft(
      size: size,
      anchor: anchor,
      approxWidth: toolbarW,
      approxHeight: toolbarH,
      preferAbove: true,
    );

    var panelTop = toolbarPos.dy + toolbarH + 8;
    if (panelTop + panelH > size.height - 8) {
      panelTop = toolbarPos.dy - panelH - 8;
    }

    final minTop = _safePaddingTop + 8.0;
    final maxTop = max(minTop, size.height - 8.0 - panelH);
    final panelPos = Offset(
      toolbarPos.dx,
      panelTop.clamp(minTop, maxTop).toDouble(),
    );

    final startOffset = reader.engine.getOffsetForTextPosition(s);
    final endOffset = reader.engine.getOffsetForTextPosition(e);

    final widgets = <Widget>[];

    // 选择手柄：仅在端点位于当前页时显示
    if (startOffset != null) {
      widgets.add(
        Positioned(
          left: startOffset.dx - 22,
          top: startOffset.dy - 22,
          child: GestureDetector(
            onPanStart: (d) => _onHandlePanStart(_DragHandle.start, d),
            onPanUpdate: _onHandlePanUpdate,
            onPanEnd: _onHandlePanEnd,
            behavior: HitTestBehavior.translucent,
            child: const SizedBox(
              width: 44,
              height: 44,
              child: Center(child: ReaderSelectionHandle()),
            ),
          ),
        ),
      );
    }

    if (endOffset != null) {
      widgets.add(
        Positioned(
          left: endOffset.dx - 22,
          top: endOffset.dy - 22,
          child: GestureDetector(
            onPanStart: (d) => _onHandlePanStart(_DragHandle.end, d),
            onPanUpdate: _onHandlePanUpdate,
            onPanEnd: _onHandlePanEnd,
            behavior: HitTestBehavior.translucent,
            child: const SizedBox(
              width: 44,
              height: 44,
              child: Center(child: ReaderSelectionHandle()),
            ),
          ),
        ),
      );
    }

    final active = _activeAnnotationId != null ? _findAnnotationById(_activeAnnotationId!) : null;
    final canDeleteHighlight = active != null && active.kind == TextAnnotationKind.highlight;

    // 工具条
    if (_showAnnotationBar) {
      widgets.add(
        Positioned(
          left: toolbarPos.dx,
          top: toolbarPos.dy,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: size.width - 16),
            child: ReaderAnnotationToolbar(
              onCopy: () => unawaited(_copySelection()),
              onHighlight: () => _applyHighlight(showStylePanel: true),
              onNote: () => unawaited(_createNoteForSelection()),
              onDismiss: _clearSelection,
              onDelete: canDeleteHighlight ? _deleteActiveHighlight : null,
              extraOptions: widget.extraToolOptions,
            ),
          ),
        ),
      );
    }

    // 样式面板
    if (_showStylePanel) {
      widgets.add(
        Positioned(
          left: panelPos.dx,
          top: panelPos.dy,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: size.width - 16),
            child: ReaderAnnotationStylePanel(
              selectedType: _editStyleType,
              selectedColor: _editColor,
              onTypeChanged: (t) {
                setState(() => _editStyleType = t);
                _applyHighlight(type: t, showStylePanel: true);
              },
              onColorChanged: (c) {
                setState(() => _editColor = c);
                _applyHighlight(color: c, showStylePanel: true);
              },
            ),
          ),
        ),
      );
    }

    return widgets;
  }

  /// 阅读器区域点击：
  /// selectionMode → 取消选择；
  /// 否则：优先命中标注（高亮优先）→ 链接 → 代码块 → 图片 → 中间区域菜单
  void _onReaderTap(TapUpDetails details) {
    final reader = _readerKey.currentState;
    if (reader == null) return;

    if (_selectionMode) {
      _clearSelection();
      return;
    }

    final dx = details.localPosition.dx;
    final dy = details.localPosition.dy;

    // 0. 标注命中（高亮优先）
    final pos = reader.engine.findTextPosition(dx, dy, preferCharLevel: false);
    if (pos != null) {
      final hit = _hitTestAnnotation(pos);
      if (hit != null) {
        if (hit.kind == TextAnnotationKind.highlight) {
          // 进入高亮编辑态（显示样式/颜色面板）
          setState(() {
            _selectionAnchorLocal = details.localPosition;
            _editStyleType = hit.style.type;
            _editColor = hit.style.color;
          });
          _setSelectionRange(
            hit.start,
            hit.end,
            activeAnnotationId: hit.id,
            showStylePanel: true,
          );
        } else {
          // 想法：先展示内容再编辑
          unawaited(_openNote(hit));
        }
        return;
      }
    }

    // 1. 链接
    final linkUrl = reader.findLinkAtPosition(dx, dy);
    if (linkUrl != null && linkUrl.isNotEmpty) {
      _openLink(linkUrl);
      return;
    }

    // 2. 代码块
    final codeBlock = reader.findCodeBlockAtPosition(dx, dy);
    if (codeBlock != null) {
      _onCodeBlockTap(codeBlock.language, codeBlock.lines);
      return;
    }

    // 3. 图片
    final image = reader.findImageAtPosition(dx, dy);
    if (image != null) {
      _onImageTap(image);
      return;
    }

    // 4. 中间 1/3 区域切换菜单
    final width = context.size?.width ?? 0;
    if (dx > width / 3 && dx < width * 2 / 3) {
      _toggleMenu();
    }
  }

  void _onReaderLongPressStart(LongPressStartDetails details) {
    final reader = _readerKey.currentState;
    if (reader == null) return;

    setState(() {
      _selectionAnchorLocal = details.localPosition;
    });

    final dx = details.localPosition.dx;
    final dy = details.localPosition.dy;

    final area = reader.engine.findHitArea(dx, dy);
    final pos = reader.engine.findTextPosition(dx, dy);
    if (area == null || pos == null) return;

    // 使用 area 的字符范围信息，避免依赖 element.length
    final maxChar = area.charIndex + (area.length > 0 ? area.length : 1);
    var startChar = pos.charIndex;
    if (startChar >= maxChar) {
      startChar = maxChar - 1;
      if (startChar < area.charIndex) startChar = area.charIndex;
    }
    final endChar = (startChar + 1 <= maxChar) ? (startChar + 1) : maxChar;

    setState(() {
      _activeAnnotationId = null;
      _showStylePanel = false;
      _editStyleType = TextAnnotationStyleType.background;
      _editColor = kAnnotationColors.last;
    });

    _setSelectionRange(
      TextFixedPosition(
        chapterIndex: pos.chapterIndex,
        paragraphIndex: pos.paragraphIndex,
        elementIndex: pos.elementIndex,
        charIndex: startChar,
      ),
      TextFixedPosition(
        chapterIndex: pos.chapterIndex,
        paragraphIndex: pos.paragraphIndex,
        elementIndex: pos.elementIndex,
        charIndex: endChar,
      ),
    );
  }

  /// 代码块点击处理
  void _onCodeBlockTap(String? language, List<String> lines) {
    _showCodeBlockSheet(context, language, lines);
  }

  /// 图片点击处理（默认行为：全屏查看）
  void _onImageTap(dynamic image) {
    // 后续可扩展为全屏查看
  }

  /// 弹出代码块 BottomSheet
  static void _showCodeBlockSheet(
      BuildContext context, String? language, List<String> lines) {
    final langLabel = (language != null && language.isNotEmpty) ? language : 'Code';
    final code = lines.join('\n');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final maxH = MediaQuery.of(ctx).size.height * 0.75;
        return Container(
          constraints: BoxConstraints(maxHeight: maxH),
          decoration: const BoxDecoration(
            color: Color(0xFFF6F8FA),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题栏
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFFE1E4E8), width: 0.5)),
                ),
                child: Row(
                  children: [
                    const Text('</>', style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700,
                      color: Color(0xFF6A737D), fontFamily: 'monospace',
                    )),
                    const SizedBox(width: 8),
                    Text(langLabel, style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600,
                      color: Color(0xFF24292E),
                    )),
                    const Spacer(),
                    // 复制按钮
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: code));
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text('代码已复制'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE1E4E8),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('复制', style: TextStyle(
                          fontSize: 13, color: Color(0xFF24292E),
                        )),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => Navigator.of(ctx).pop(),
                      child: const Icon(Icons.close, size: 20, color: Color(0xFF959DA5)),
                    ),
                  ],
                ),
              ),
              // 代码区域
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  scrollDirection: Axis.vertical,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SelectableText(
                      code,
                      style: const TextStyle(
                        fontSize: 13,
                        fontFamily: 'monospace',
                        height: 1.5,
                        color: Color(0xFF24292E),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 打开链接
  void _openLink(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      // 外部链接：显示确认对话框
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('打开链接'),
          content: Text('是否打开\n$url'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              },
              child: const Text('打开'),
            ),
          ],
        ),
      );
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
          // 不需要显式调用 updateTextConfig —— setState 触发 rebuild 后
          // didUpdateWidget 会检测到 textConfig 变化并自动调用 setTextConfig
        }
      });
    }

    final bgColor = Color(_textConfig.bgColor);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: bgColor,
      // 阅读器不应随键盘弹出而缩小，避免触发重新分页导致位置丢失
      resizeToAvoidBottomInset: false,
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
            child: Container(
              key: _readerBoxKey,
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
                onShowNoteBottomSheet: widget.onShowNote == null
                    ? null
                    : (ctx, note, selectedText, isEdit, onCancel, onConfirm) {
                        unawaited(() async {
                          final text = await widget.onShowNote!(ctx, note);
                          if (text == null) {
                            onCancel();
                          } else {
                            onConfirm(text);
                          }
                        }());
                      },
                selectionMode: _selectionMode,
                safePaddingTop: _safePaddingTop,
              ),
            ),
          ),

          // 居中点击检测层（与 TextReaderWidget 的 pan 手势通过手势竞技场自动区分）
          if (!_showMenu)
            Positioned.fill(
              child: GestureDetector(
                onTapUp: _onReaderTap,
                onLongPressStart: _onReaderLongPressStart,
                behavior: HitTestBehavior.translucent,
              ),
            ),

          ..._buildAnnotationOverlays(context),

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
