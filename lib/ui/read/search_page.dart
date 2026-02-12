import 'dart:async';

import 'package:flutter/material.dart';

import '../../text/search/text_search_engine.dart';

/// 搜索页面
/// 全屏搜索页，流式显示搜索结果，点击跳转到对应章节
class SearchPage extends StatefulWidget {
  final TextSearchEngine searchEngine;

  const SearchPage({super.key, required this.searchEngine});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _results = <SearchResult>[];

  StreamSubscription? _searchSub;
  Timer? _debounce;

  bool _isSearching = false;
  int _searchedChapters = 0;
  int _totalChapters = 0;
  String _currentKeyword = '';

  @override
  void initState() {
    super.initState();
    // 自动聚焦搜索框
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchSub?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _startSearch(text.trim());
    });
  }

  void _startSearch(String keyword) {
    // 取消上一次搜索
    _searchSub?.cancel();

    setState(() {
      _results.clear();
      _isSearching = keyword.isNotEmpty;
      _searchedChapters = 0;
      _totalChapters = 0;
      _currentKeyword = keyword;
    });

    if (keyword.isEmpty) return;

    _searchSub = widget.searchEngine
        .search(keyword)
        .listen(
          (event) {
            if (!mounted) return;
            if (event.result != null) {
              setState(() => _results.add(event.result!));
            }
            if (event.progress != null) {
              setState(() {
                _searchedChapters = event.progress!.currentChapterIndex;
                _totalChapters = event.progress!.totalChapters;
                if (event.progress!.isComplete) {
                  _isSearching = false;
                }
              });
            }
          },
          onDone: () {
            if (mounted) setState(() => _isSearching = false);
          },
          onError: (_) {
            if (mounted) setState(() => _isSearching = false);
          },
        );
  }

  void _onResultTap(SearchResult result) {
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F0E8),
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchBar(),
            _buildStatusBar(),
            Expanded(child: _buildResultList()),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
      decoration: const BoxDecoration(
        color: Color(0xFFF5F0E8),
        border: Border(
          bottom: BorderSide(color: Color(0xFFD0C8B8), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFF555555)),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFEDE7D9),
                borderRadius: BorderRadius.circular(20),
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                onChanged: _onSearchChanged,
                onSubmitted: (text) => _startSearch(text.trim()),
                style: const TextStyle(fontSize: 15, color: Color(0xFF333333)),
                decoration: InputDecoration(
                  hintText: '输入搜索关键词...',
                  hintStyle: const TextStyle(
                    color: Color(0xFF999999),
                    fontSize: 15,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  suffixIcon: _controller.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear,
                              size: 18, color: Color(0xFF999999)),
                          onPressed: () {
                            _controller.clear();
                            _startSearch('');
                          },
                        )
                      : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    String statusText;
    if (_currentKeyword.isEmpty) {
      statusText = '输入关键词开始搜索';
    } else if (_isSearching) {
      statusText = '搜索中 $_searchedChapters/$_totalChapters 章节... '
          '已找到 ${_results.length} 个结果';
    } else {
      statusText = '搜索完成，共 ${_results.length} 个结果';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFFE0D8C8), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          if (_isSearching)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF8B6914),
                ),
              ),
            ),
          Expanded(
            child: Text(
              statusText,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF888888),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultList() {
    if (_results.isEmpty && !_isSearching && _currentKeyword.isNotEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: Color(0xFFCCCCCC)),
            SizedBox(height: 12),
            Text('未找到相关内容',
                style: TextStyle(color: Color(0xFF999999), fontSize: 15)),
          ],
        ),
      );
    }

    if (_results.isEmpty && _currentKeyword.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 48, color: Color(0xFFDDD8CC)),
            SizedBox(height: 12),
            Text('全文搜索',
                style: TextStyle(color: Color(0xFF999999), fontSize: 15)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _results.length,
      padding: EdgeInsets.zero,
      itemBuilder: (context, index) {
        final result = _results[index];
        return _buildResultItem(result);
      },
    );
  }

  Widget _buildResultItem(SearchResult result) {
    return InkWell(
      onTap: () => _onResultTap(result),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0xFFE0D8C8), width: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 章节标题
            Text(
              result.chapterTitle,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF8B6914),
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            // 匹配上下文（关键词高亮）
            _buildHighlightedContext(result),
          ],
        ),
      ),
    );
  }

  /// 构建关键词高亮的上下文文本
  Widget _buildHighlightedContext(SearchResult result) {
    final text = result.contextText;
    final kwStart = result.keywordStartInContext;
    final kwEnd = kwStart + result.keyword.length;

    // 安全边界检查
    if (kwStart < 0 || kwEnd > text.length) {
      return Text(
        text,
        style: const TextStyle(fontSize: 14, color: Color(0xFF555555)),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }

    final before = text.substring(0, kwStart);
    final keyword = text.substring(kwStart, kwEnd);
    final after = text.substring(kwEnd);

    // 上下文可能是截断的片段，在两端添加省略号
    final showLeadingEllipsis = kwStart > 0;
    final showTrailingEllipsis = kwEnd < text.length && after.isNotEmpty;

    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: const TextStyle(fontSize: 14, color: Color(0xFF555555)),
        children: [
          if (before.isNotEmpty)
            TextSpan(text: showLeadingEllipsis ? '...$before' : before),
          TextSpan(
            text: keyword,
            style: const TextStyle(
              color: Color(0xFFE65100),
              fontWeight: FontWeight.w600,
              backgroundColor: Color(0x22FF9800),
            ),
          ),
          if (after.isNotEmpty)
            TextSpan(text: showTrailingEllipsis ? '$after...' : after),
        ],
      ),
    );
  }
}
