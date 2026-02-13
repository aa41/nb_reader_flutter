import 'package:flutter/material.dart';

import '../../text/annotation/text_annotation.dart';

/// 标注颜色面板（与 1.jpg 类似：5 个颜色点，选中显示对勾）
const List<int> kAnnotationColors = <int>[
  0xFFE57373, // red
  0xFF9575CD, // purple
  0xFF64B5F6, // blue
  0xFF81C784, // green
  0xFFFFF176, // yellow
];

/// 自定义工具选项
class AnnotationToolOption {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const AnnotationToolOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

class ReaderAnnotationToolbar extends StatelessWidget {
  final VoidCallback onCopy;
  final VoidCallback onHighlight;
  final VoidCallback onNote;
  final VoidCallback onDismiss;
  final VoidCallback? onDelete;

  /// 自定义选项，显示在"写想法"后面
  final List<AnnotationToolOption> extraOptions;

  const ReaderAnnotationToolbar({
    super.key,
    required this.onCopy,
    required this.onHighlight,
    required this.onNote,
    required this.onDismiss,
    this.onDelete,
    this.extraOptions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final maxWidth = screenWidth * 2 / 3;

    final items = <Widget>[
      _ToolItem(icon: Icons.copy_rounded, label: '复制', onTap: onCopy),
      const SizedBox(width: 10),
      if (onDelete != null) ...[
        _ToolItem(icon: Icons.format_color_reset_rounded, label: '删除划线', onTap: onDelete!),
        const SizedBox(width: 10),
      ] else ...[
        _ToolItem(icon: Icons.edit, label: '划线', onTap: onHighlight),
        const SizedBox(width: 10),
      ],
      _ToolItem(icon: Icons.mode_comment_outlined, label: '写想法', onTap: onNote),
      for (final opt in extraOptions) ...[
        const SizedBox(width: 10),
        _ToolItem(icon: opt.icon, label: opt.label, onTap: opt.onTap),
      ],
    ];

    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF2B2B2B),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            )
          ],
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: items,
          ),
        ),
      ),
    );
  }
}

class ReaderAnnotationStylePanel extends StatelessWidget {
  final TextAnnotationStyleType selectedType;
  final int selectedColor;
  final ValueChanged<TextAnnotationStyleType> onTypeChanged;
  final ValueChanged<int> onColorChanged;
  final List<int> colors;

  const ReaderAnnotationStylePanel({
    super.key,
    required this.selectedType,
    required this.selectedColor,
    required this.onTypeChanged,
    required this.onColorChanged,
    this.colors = kAnnotationColors,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final maxWidth = screenWidth * 2 / 3;

    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF2B2B2B),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            )
          ],
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StyleItem(
                type: TextAnnotationStyleType.background,
                selected: selectedType == TextAnnotationStyleType.background,
                onTap: () => onTypeChanged(TextAnnotationStyleType.background),
              ),
              const SizedBox(width: 8),
              _StyleItem(
                type: TextAnnotationStyleType.underline,
                selected: selectedType == TextAnnotationStyleType.underline,
                onTap: () => onTypeChanged(TextAnnotationStyleType.underline),
              ),
              const SizedBox(width: 8),
              _StyleItem(
                type: TextAnnotationStyleType.wavyUnderline,
                selected: selectedType == TextAnnotationStyleType.wavyUnderline,
                onTap: () => onTypeChanged(TextAnnotationStyleType.wavyUnderline),
              ),
              const SizedBox(width: 10),
              for (final c in colors) ...[
                _ColorDot(
                  color: Color(c),
                  selected: c == selectedColor,
                  onTap: () => onColorChanged(c),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ReaderSelectionHandle extends StatelessWidget {
  final Color color;

  const ReaderSelectionHandle({
    super.key,
    this.color = const Color(0xFFFFD54F),
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
      ),
    );
  }
}

class _ToolItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ToolItem({
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
        width: 42,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            if (label.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 10,
                  height: 1.1,
                ),
                maxLines: 1,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.white : Colors.transparent,
            width: 1.5,
          ),
        ),
        alignment: Alignment.center,
        child: selected
            ? const Icon(Icons.check, size: 12, color: Colors.black87)
            : null,
      ),
    );
  }
}

class _StyleItem extends StatelessWidget {
  final TextAnnotationStyleType type;
  final bool selected;
  final VoidCallback onTap;

  const _StyleItem({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: selected ? Colors.white.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? Colors.white : Colors.white.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        alignment: Alignment.center,
        child: _StyleIcon(type: type),
      ),
    );
  }
}

class _StyleIcon extends StatelessWidget {
  final TextAnnotationStyleType type;

  const _StyleIcon({required this.type});

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.w700,
      fontSize: 13,
      height: 1.0,
    );

    return CustomPaint(
      painter: _StyleIconPainter(type: type),
      child: const SizedBox(
        width: 20,
        height: 20,
        child: Center(child: Text('A', style: textStyle)),
      ),
    );
  }
}

class _StyleIconPainter extends CustomPainter {
  final TextAnnotationStyleType type;

  _StyleIconPainter({required this.type});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    final y = size.height - 4;
    const left = 4.0;
    final right = size.width - 4;

    switch (type) {
      case TextAnnotationStyleType.background:
        final rect = Rect.fromLTWH(2, 6, size.width - 4, size.height - 10);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(4)),
          Paint()..color = Colors.white.withValues(alpha: 0.2)..style = PaintingStyle.fill,
        );
        break;
      case TextAnnotationStyleType.underline:
        canvas.drawLine(Offset(left, y), Offset(right, y), paint);
        break;
      case TextAnnotationStyleType.wavyUnderline:
        final path = Path();
        path.moveTo(left, y);
        const waveLen = 6.0;
        const amp = 2.0;
        double x = left;
        bool up = true;
        while (x < right) {
          final nx = (x + waveLen).clamp(left, right);
          final mx = (x + nx) / 2;
          final cy = y + (up ? -amp : amp);
          path.quadraticBezierTo(mx, cy, nx, y);
          up = !up;
          x = nx;
        }
        canvas.drawPath(path, paint);
        break;
      case TextAnnotationStyleType.dashedUnderline:
        canvas.drawLine(Offset(left, y), Offset(right, y), paint);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _StyleIconPainter oldDelegate) {
    return oldDelegate.type != type;
  }
}
