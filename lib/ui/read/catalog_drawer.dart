import 'package:flutter/material.dart';

import '../../text/entity/text_chapter.dart';

/// 目录侧边栏
class CatalogDrawer extends StatelessWidget {
  final String bookTitle;
  final List<TextChapter> chapters;
  final int currentChapterIndex;
  final ValueChanged<int> onChapterTap;

  const CatalogDrawer({
    super.key,
    required this.bookTitle,
    required this.chapters,
    required this.currentChapterIndex,
    required this.onChapterTap,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: 300,
      child: Container(
        color: const Color(0xFFF5F0E8),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 书名标题
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Text(
                  bookTitle,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF333333),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(height: 1, color: Color(0xFFD0C8B8)),
              // 章节列表
              Expanded(
                child: ListView.builder(
                  itemCount: chapters.length,
                  padding: EdgeInsets.zero,
                  itemBuilder: (context, index) {
                    final chapter = chapters[index];
                    final isCurrent = index == currentChapterIndex;
                    return InkWell(
                      onTap: () => onChapterTap(index),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? const Color(0xFFE8DFD0)
                              : Colors.transparent,
                          border: const Border(
                            bottom: BorderSide(
                              color: Color(0xFFE0D8C8),
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: Text(
                          chapter.title,
                          style: TextStyle(
                            fontSize: 15,
                            color: isCurrent
                                ? const Color(0xFF8B6914)
                                : const Color(0xFF555555),
                            fontWeight: isCurrent
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
