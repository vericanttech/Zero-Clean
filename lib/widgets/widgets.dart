// ─────────────────────────────────────────────
//  ZERO-CLEAN  ·  Shared Widgets
// ─────────────────────────────────────────────

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';
import '../models/models.dart';
import '../providers/app_state.dart';

// ── Progress Ring ─────────────────────────────

class ProgressRing extends StatelessWidget {
  final double pct; // 0.0 – 2.0
  final double size;
  final Widget? child;
  final bool showLabel;

  const ProgressRing({
    super.key,
    required this.pct,
    this.size = 64,
    this.child,
    this.showLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = ZCTheme.progressColor(pct);
    final display = (pct * 100).clamp(0, 999).toInt();
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(pct: pct.clamp(0, 1), color: color),
          ),
          child ??
              Text(
                showLabel ? '$display%' : ZCTheme.progressEmoji(pct),
                style: TextStyle(
                  fontSize: size * 0.22,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double pct;
  final Color color;
  _RingPainter({required this.pct, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = (size.width / 2) - 6;
    final strokeW = 5.0;

    // Track
    canvas.drawCircle(
      Offset(cx, cy),
      radius,
      Paint()
        ..color = ZCTheme.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW,
    );

    // Arc
    if (pct > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: radius),
        -math.pi / 2,
        2 * math.pi * pct,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeW
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.pct != pct || old.color != color;
}

// ── Variant Progress Card ─────────────────────

class VariantCard extends StatelessWidget {
  final VariantSummary summary;
  final VoidCallback? onTap;

  const VariantCard({super.key, required this.summary, this.onTap});

  @override
  Widget build(BuildContext context) {
    final v = summary.variant;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              ProgressRing(pct: summary.overallPct, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      v.fullLabel,
                      style: const TextStyle(
                        color: ZCTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      v.category,
                      style: const TextStyle(
                          color: ZCTheme.textMuted, fontSize: 11),
                    ),
                    const SizedBox(height: 8),
                    _ContextBars(progress: summary.progress),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContextBars extends StatelessWidget {
  final List<Progress> progress;
  const _ContextBars({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: CaptureContext.values.map((ctx) {
        try {
          final p = progress.firstWhere((pr) => pr.context == ctx);
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ctx.labelFr.toUpperCase(),
                    style: const TextStyle(
                        color: ZCTheme.textMuted,
                        fontSize: 9,
                        letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 2),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: p.pct.clamp(0, 1),
                      minHeight: 4,
                      backgroundColor: ZCTheme.border,
                      color: ZCTheme.progressColor(p.pct),
                    ),
                  ),
                  Text(
                    '${p.currentCount}/${p.targetCap}',
                    style: const TextStyle(
                        color: ZCTheme.textSecondary, fontSize: 9),
                  ),
                ],
              ),
            ),
          );
        } catch (_) {
          return const Expanded(child: SizedBox());
        }
      }).toList(),
    );
  }
}

// ── Section Header ────────────────────────────

class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const SectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: ZCTheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// ── Stat Tile ─────────────────────────────────

class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const StatTile(
      {super.key, required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: ZCTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ZCTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: ZCTheme.textMuted, fontSize: 11, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? ZCTheme.accent,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              fontFamily: ZCTheme.fontMono,
            ),
          ),
        ],
      ),
    );
  }
}

// ── ZC Dropdown ───────────────────────────────

class ZCDropdown<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final bool enabled;

  const ZCDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: ZCTheme.textSecondary, fontSize: 11, letterSpacing: 0.5)),
        const SizedBox(height: 4),
        DropdownButtonFormField<T>(
          value: value,
          isExpanded: true,
          items: items,
          onChanged: enabled ? onChanged : null,
          dropdownColor: ZCTheme.surfaceAlt,
          style: const TextStyle(color: ZCTheme.textPrimary, fontSize: 14),
          iconEnabledColor: ZCTheme.accent,
          iconDisabledColor: ZCTheme.textMuted,
          decoration: InputDecoration(
            enabled: enabled,
            filled: true,
            fillColor: enabled ? ZCTheme.surfaceAlt : ZCTheme.surface,
          ),
        ),
      ],
    );
  }
}

// ── Context Selector Chips ────────────────────

class ContextSelector extends StatelessWidget {
  final CaptureContext selected;
  final ValueChanged<CaptureContext> onChanged;
  /// Optional display labels (e.g. French). When null, uses enum name.
  final Map<CaptureContext, String>? displayLabels;

  const ContextSelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.displayLabels,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: CaptureContext.values.map((ctx) {
        final isSelected = ctx == selected;
        final label = displayLabels?[ctx] ?? ctx.name.toUpperCase();
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(ctx),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? ZCTheme.accent.withOpacity(0.15) : ZCTheme.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? ZCTheme.accent : ZCTheme.border,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    ctx == CaptureContext.single
                        ? '📦'
                        : ctx == CaptureContext.shelf
                            ? '🏪'
                            : '🛒',
                    style: const TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label.toUpperCase(),
                    style: TextStyle(
                      color: isSelected ? ZCTheme.accent : ZCTheme.textMuted,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Empty State ────────────────────────────────

class EmptyState extends StatelessWidget {
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState(
      {super.key, required this.message, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📭', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: ZCTheme.textSecondary, fontSize: 14)),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
            ]
          ],
        ),
      ),
    );
  }
}
