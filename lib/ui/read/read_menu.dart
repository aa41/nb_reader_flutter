import 'package:flutter/material.dart';

import '../../widget/page_enum.dart';

/// 底部阅读菜单
class ReadBottomMenu extends StatelessWidget {
  final VoidCallback onCatalogTap;
  final VoidCallback onNightModeTap;
  final VoidCallback onSettingTap;
  final VoidCallback onBookmarkTap;
  final bool isNightMode;

  const ReadBottomMenu({
    super.key,
    required this.onCatalogTap,
    required this.onNightModeTap,
    required this.onSettingTap,
    required this.onBookmarkTap,
    this.isNightMode = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xCC333333),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 功能按钮行
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _MenuButton(
                    icon: Icons.list,
                    label: '目录',
                    onTap: onCatalogTap,
                  ),
                  _MenuButton(
                    icon: Icons.bookmark_border,
                    label: '书签',
                    onTap: onBookmarkTap,
                  ),
                  _MenuButton(
                    icon: isNightMode ? Icons.wb_sunny : Icons.nightlight_round,
                    label: isNightMode ? '日间' : '夜间',
                    onTap: onNightModeTap,
                  ),
                  _MenuButton(
                    icon: Icons.settings,
                    label: '设置',
                    onTap: onSettingTap,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 70,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// 设置面板（字号、行间距、字间距、边距、翻页动画）
class ReadSettingPanel extends StatelessWidget {
  final int fontSize;
  final int lineSpacePercent;
  final double letterSpacing;
  final int marginHorizontal;
  final int marginVertical;
  final PageAnimType animType;
  final ValueChanged<int> onFontSizeChanged;
  final ValueChanged<int> onLineSpaceChanged;
  final ValueChanged<double> onLetterSpacingChanged;
  final ValueChanged<int> onMarginHorizontalChanged;
  final ValueChanged<int> onMarginVerticalChanged;
  final ValueChanged<PageAnimType> onAnimTypeChanged;

  const ReadSettingPanel({
    super.key,
    required this.fontSize,
    required this.lineSpacePercent,
    required this.letterSpacing,
    required this.marginHorizontal,
    required this.marginVertical,
    required this.animType,
    required this.onFontSizeChanged,
    required this.onLineSpaceChanged,
    required this.onLetterSpacingChanged,
    required this.onMarginHorizontalChanged,
    required this.onMarginVerticalChanged,
    required this.onAnimTypeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xCC333333),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 字号调节
              _buildSettingRow(
                icon: Icons.text_fields,
                label: '字号 $fontSize',
                onDecrease: fontSize > 12 ? () => onFontSizeChanged(fontSize - 2) : null,
                onIncrease: fontSize < 36 ? () => onFontSizeChanged(fontSize + 2) : null,
              ),
              const SizedBox(height: 10),
              // 行间距调节
              _buildSettingRow(
                icon: Icons.format_line_spacing,
                label: '行距 $lineSpacePercent%',
                onDecrease: lineSpacePercent > 100 ? () => onLineSpaceChanged(lineSpacePercent - 10) : null,
                onIncrease: lineSpacePercent < 200 ? () => onLineSpaceChanged(lineSpacePercent + 10) : null,
              ),
              const SizedBox(height: 10),
              // 字间距调节
              _buildSettingRow(
                icon: Icons.space_bar,
                label: '字距 ${letterSpacing.toStringAsFixed(1)}',
                onDecrease: letterSpacing > 0 ? () => onLetterSpacingChanged(letterSpacing - 0.5) : null,
                onIncrease: letterSpacing < 5 ? () => onLetterSpacingChanged(letterSpacing + 0.5) : null,
              ),
              const SizedBox(height: 10),
              // 左右边距调节
              _buildSettingRow(
                icon: Icons.swap_horiz,
                label: '左右边距 $marginHorizontal',
                onDecrease: marginHorizontal > 5 ? () => onMarginHorizontalChanged(marginHorizontal - 5) : null,
                onIncrease: marginHorizontal < 60 ? () => onMarginHorizontalChanged(marginHorizontal + 5) : null,
              ),
              const SizedBox(height: 10),
              // 上下边距调节
              _buildSettingRow(
                icon: Icons.swap_vert,
                label: '上下边距 $marginVertical',
                onDecrease: marginVertical > 5 ? () => onMarginVerticalChanged(marginVertical - 5) : null,
                onIncrease: marginVertical < 60 ? () => onMarginVerticalChanged(marginVertical + 5) : null,
              ),
              const SizedBox(height: 14),
              // 翻页动画选择
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _animChip('无', PageAnimType.none),
                  _animChip('滑动', PageAnimType.slide),
                  _animChip('覆盖', PageAnimType.cover),
                  _animChip('仿真', PageAnimType.simulation),
                  _animChip('滚动', PageAnimType.scroll),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingRow({
    required IconData icon,
    required String label,
    VoidCallback? onDecrease,
    VoidCallback? onIncrease,
  }) {
    return Row(
      children: [
        Icon(icon, color: Colors.white54, size: 18),
        const SizedBox(width: 8),
        _settingIconButton(Icons.remove, onDecrease),
        Expanded(
          child: Center(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ),
        _settingIconButton(Icons.add, onIncrease),
      ],
    );
  }

  Widget _settingIconButton(IconData icon, VoidCallback? onTap) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 30,
        decoration: BoxDecoration(
          border: Border.all(color: enabled ? Colors.white54 : Colors.white24),
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: enabled ? Colors.white : Colors.white30, size: 18),
      ),
    );
  }

  Widget _animChip(String label, PageAnimType type) {
    final selected = animType == type;
    return GestureDetector(
      onTap: () => onAnimTypeChanged(type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF8B6914) : Colors.transparent,
          border: Border.all(
            color: selected ? const Color(0xFF8B6914) : Colors.white54,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
