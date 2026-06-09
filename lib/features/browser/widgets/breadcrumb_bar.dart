// lib/features/browser/widgets/breadcrumb_bar.dart
// Breadcrumb navigation bar for the Browser feature (BRW-02).
//
// Displays the current directory path as a horizontal row of tappable
// chips.  Each segment navigates to the corresponding directory level.
// When the row overflows the available width, leftmost segments (after
// root) are collapsed into a "…" chip that opens a popup menu.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../browser_provider.dart';

// ── Public API ────────────────────────────────────────────────────────────────────

/// A horizontal breadcrumb bar that displays the directory navigation path.
///
/// Reads [navigationStackProvider] to obtain the current path stack and
/// calls [NavigationStackNotifier.popTo] when a segment is tapped.
///
/// When the full breadcrumb row overflows the available width, segments
/// between the root and the rightmost visible ones are collapsed into a
/// single "…" chip.  Tapping "…" opens a popup menu listing the hidden
/// paths so the user can jump to any level.
class BreadcrumbBar extends ConsumerWidget {
  const BreadcrumbBar({super.key});

  // ── Layout constants ──────────────────────────────────────────────────────────

  static const double _chipHorizontalPadding = 4.0;
  static const double _chipVerticalPadding = 6.0;
  static const double _separatorWidth =
      16.0; // width of the "/" label between chips
  static const double _overflowChipWidth =
      36.0; // approximate width of "…" chip

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stack = ref.watch(navigationStackProvider);
    final notifier = ref.read(navigationStackProvider.notifier);
    final theme = Theme.of(context);
    final textStyle = (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
      color: theme.colorScheme.primary,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: 8, vertical: _chipVerticalPadding),
      color: theme.colorScheme.surfaceContainerHighest,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth;

          // Derive display-name + full-path pairs from the stack.
          final segments = _buildPathSegments(stack);

          // Measure each segment's chip width (text + padding).
          final textPainter =
              TextPainter(textDirection: Directionality.of(context))
                ..text = TextSpan(text: '…', style: textStyle)
                ..layout();
          final measuredWidths = <double>[];
          for (final seg in segments) {
            textPainter.text =
                TextSpan(text: seg.displayName, style: textStyle);
            textPainter.layout(maxWidth: availableWidth);
            measuredWidths.add(textPainter.width + _chipHorizontalPadding * 2);
          }

          // Compute which indices are visible / collapsed.
          final layout = computeBreadcrumbLayout(
            segmentCount: segments.length,
            measuredWidths: measuredWidths,
            availableWidth: availableWidth,
            overflowChipWidth: _overflowChipWidth,
            separatorWidth: _separatorWidth,
          );

          // Build the actual chip row.
          final chips = <Widget>[];
          for (int i = 0; i < segments.length; i++) {
            final seg = segments[i];

            if (i > 0 && chips.isNotEmpty && !layout.collapsed.contains(i)) {
              // Separator
              chips.add(_SeparatorLabel(style: textStyle));
            }

            if (layout.collapsed.contains(i)) {
              // All collapsed segments are rendered as a single "…" chip
              // (only once, when we encounter the first collapsed index).
              if (i == layout.collapsed.first) {
                final collapsedSegs =
                    layout.collapsed.map((idx) => segments[idx]).toList();
                chips.add(_OverflowChip(
                  collapsedSegments: collapsedSegs,
                  notifier: notifier,
                  style: textStyle,
                ));
              }
              continue;
            }

            if (layout.visible.contains(i)) {
              chips.add(_SegmentChip(
                segment: seg,
                notifier: notifier,
                style: textStyle,
                isLast: i == segments.length - 1,
              ));
            }
          }
          // I-5: release native resources held by the TextPainter.
          textPainter.dispose();

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: chips),
          );
        },
      ),
    );
  }
}

// ── Path-segment helpers ──────────────────────────────────────────────────────────

/// Internal representation of a single breadcrumb path segment.
class _PathSegment {
  final String displayName; // user-visible label (e.g. "music", "根目录")
  final String fullPath; // absolute path for navigation
  const _PathSegment({required this.displayName, required this.fullPath});
}

/// Converts a navigation stack (list of absolute paths) into display-ready
/// [_PathSegment] objects.
///
/// The root path "/" is displayed as "根目录"; deeper paths show only their
/// last component (e.g. "/music/artist" → "artist").
List<_PathSegment> _buildPathSegments(List<String> pathStack) {
  return pathStack.map((path) {
    final isRoot = path == '/' || path.isEmpty;
    final displayName = isRoot ? '根目录' : path.split('/').last;
    return _PathSegment(displayName: displayName, fullPath: path);
  }).toList();
}

// ── Overflow-collapse layout logic (pure function for testability) ────────────────

/// Computes which breadcrumb segment indices should be visible and which
/// should be collapsed behind an overflow "…" chip.
///
/// [segmentCount] is the total number of path segments.
/// [measuredWidths] is the pre-measured pixel width of each segment chip
/// (including internal padding but excluding inter-chip separators).
/// [availableWidth] is the total available horizontal space.
/// [overflowChipWidth] is the reserved width of the "…" chip (if needed).
/// [separatorWidth] is the width of the "/" label between chips.
///
/// Returns a record with two lists:
///   - [visible]: indices shown directly in the bar
///   - [collapsed]: indices hidden behind the "…" chip
///
/// Invariants:
///   - Index 0 (root) is always visible.
///   - The union of visible + collapsed == all indices.
///   - visible ∩ collapsed == ∅.
///   - collapsed is empty when everything fits.
({List<int> visible, List<int> collapsed}) computeBreadcrumbLayout({
  required int segmentCount,
  required List<double> measuredWidths,
  required double availableWidth,
  double overflowChipWidth = 36.0,
  double separatorWidth = 16.0,
}) {
  assert(segmentCount == measuredWidths.length,
      'measuredWidths length must equal segmentCount');
  assert(segmentCount >= 1, 'must have at least one segment');

  // Compute total width if all segments were shown.
  double totalWidth = 0;
  for (int i = 0; i < segmentCount; i++) {
    totalWidth += measuredWidths[i];
    if (i < segmentCount - 1) totalWidth += separatorWidth;
  }

  // Everything fits — no overflow needed.
  if (totalWidth <= availableWidth) {
    return (
      visible: List.generate(segmentCount, (i) => i),
      collapsed: [],
    );
  }

  // overflow needed.
  // Strategy: always show root (0).  Keep as many rightmost segments
  // as possible.  Everything in between goes into collapsed.

  final rootWidth = measuredWidths[0];
  // Reserve space for root + overflow chip + separator between them
  final reservedForLeft = rootWidth + overflowChipWidth + separatorWidth;
  final remainingForRight = availableWidth - reservedForLeft;

  // Collect rightmost segments that fit in the remaining space.
  final rightVisible = <int>[];
  double rightUsed = 0;
  for (int i = segmentCount - 1; i >= 1; i--) {
    double w = measuredWidths[i];
    // Add separator between this segment and the segment to its left
    // (which could be another right-visible segment or the overflow chip).
    if (rightVisible.isNotEmpty) {
      w += separatorWidth;
    }
    if (rightUsed + w <= remainingForRight) {
      rightVisible.insert(0, i);
      rightUsed += w;
    } else {
      break;
    }
  }

  // If nothing fits on the right, only root is visible.
  if (rightVisible.isEmpty) {
    return (
      visible: [0],
      collapsed: List.generate(segmentCount - 1, (i) => i + 1),
    );
  }

  // If the first right-visible segment is index 1 (adjacent to root),
  // there's no gap — show root + all right-visible segments directly.
  if (rightVisible.first == 1) {
    return (
      visible: [0, ...rightVisible],
      collapsed: [],
    );
  }

  // Gap exists: root, "…", then right-visible segments.
  final collapsed = <int>[];
  for (int i = 1; i < rightVisible.first; i++) {
    collapsed.add(i);
  }

  return (
    visible: [0, ...rightVisible],
    collapsed: collapsed,
  );
}

// ── Chip widgets ──────────────────────────────────────────────────────────────────

/// A tappable chip representing one breadcrumb path segment.
class _SegmentChip extends StatelessWidget {
  final _PathSegment segment;
  final NavigationStackNotifier notifier;
  final TextStyle style;
  final bool isLast;

  const _SegmentChip({
    required this.segment,
    required this.notifier,
    required this.style,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final labelStyle =
        isLast ? style.copyWith(fontWeight: FontWeight.bold) : style;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => notifier.popTo(segment.fullPath),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: BreadcrumbBar._chipHorizontalPadding,
            vertical: 2,
          ),
          child: Text(
            segment.displayName,
            style: labelStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

/// The "…" chip that opens a popup menu listing collapsed path segments.
class _OverflowChip extends StatelessWidget {
  final List<_PathSegment> collapsedSegments;
  final NavigationStackNotifier notifier;
  final TextStyle style;

  const _OverflowChip({
    required this.collapsedSegments,
    required this.notifier,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      offset: const Offset(0, 36),
      itemBuilder: (context) {
        return collapsedSegments.map((seg) {
          return PopupMenuItem<String>(
            value: seg.fullPath,
            child: Text(seg.displayName),
          );
        }).toList();
      },
      onSelected: (path) => notifier.popTo(path),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: BreadcrumbBar._chipHorizontalPadding,
          vertical: 2,
        ),
        child: Text('…', style: style),
      ),
    );
  }
}

/// The "/" separator label between breadcrumb chips.
class _SeparatorLabel extends StatelessWidget {
  final TextStyle style;
  const _SeparatorLabel({required this.style});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text('/', style: style.copyWith(color: Colors.grey)),
    );
  }
}
