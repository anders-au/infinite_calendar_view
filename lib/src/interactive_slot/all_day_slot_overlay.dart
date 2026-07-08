import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../utils/extension.dart';
import 'handles/slot_handle.dart';
import 'slot_config.dart';
import 'slot_controller.dart';
import 'slot_renderer.dart';
import 'slot_selection.dart';

/// Positions an all-day interactive slot in the all-day bar's [Stack] and
/// manages its horizontal drag/resize lifecycle.
///
/// The all-day bar is horizontal-only — no vertical time axis.  Drag modes
/// are [DragMode.shift] (move left/right), [DragMode.extendStart] (resize
/// left edge), and [DragMode.extendEnd] (resize right edge).  The snap step
/// is always one whole day.
class AllDaySlotOverlay extends StatefulWidget {
  const AllDaySlotOverlay({
    super.key,
    required this.slotNotifier,
    required this.config,
    required this.dayWidth,
    required this.eventHeight,
    required this.cellGapWidthPadding,
    required this.eventEndGap,
    required this.columnPositions,
    required this.initialDate,
    this.headerScrollController,
    this.mainContentScrollController,
    this.viewportLeftInset = 0,
    this.autoScrollThreshold = 40.0,
    this.autoScrollMaxSpeed = 8.0,
    this.onChanged,
    this.onDragStart,
    this.onDragEnd,
  });

  /// Notifier holding the current [CalendarSlot] (must have `isAllDay == true`).
  final ValueNotifier<CalendarSlot?> slotNotifier;

  /// Interaction configuration.  [SlotInteractionConfig.enableVerticalAxis]
  /// should be false for all-day slots.
  final SlotInteractionConfig config;

  /// Width of one day column in logical pixels.
  final double dayWidth;

  /// Height of one event row in the all-day bar.
  final double eventHeight;

  /// Half the cell-gap width.
  final double cellGapWidthPadding;

  /// Gap subtracted from the right edge (matching [FullDayParam.eventEndGap]).
  final double eventEndGap;

  /// Per-column positions `[startOffset, endOffset]` within the padded day.
  final List<double> columnPositions;

  /// The planner's initial date (used for day-index calculations).
  final DateTime initialDate;

  /// The header/all-day-bar horizontal scroll controller.
  final ScrollController? headerScrollController;

  /// The main planner content scroll controller (for auto-scroll sync).
  final ScrollController? mainContentScrollController;

  /// Inset from the left viewport edge (time-indicator column width).
  final double viewportLeftInset;

  /// Auto-scroll parameters.
  final double autoScrollThreshold;
  final double autoScrollMaxSpeed;

  /// Called whenever the slot changes.
  final void Function(CalendarSlot? slot)? onChanged;

  /// Called when a drag begins / ends.
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  @override
  State<AllDaySlotOverlay> createState() => _AllDaySlotOverlayState();
}

class _AllDaySlotOverlayState extends State<AllDaySlotOverlay> {
  DragSession? _session;
  SlotAutoScroller? _autoScroller;
  MouseCursor _effectiveCursor = SystemMouseCursors.basic;

  CalendarSlot? get _slot => widget.slotNotifier.value;

  @override
  void dispose() {
    _autoScroller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slot = _slot;
    if (slot == null || !slot.isAllDay) return const SizedBox.shrink();

    final rect = _computeRect(slot);
    if (rect.isEmpty) return const SizedBox.shrink();

    final isDragging = _session != null;
    final accent = widget.config.accentColor ?? Theme.of(context).colorScheme.secondary;

    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: MouseRegion(
        cursor: _effectiveCursor,
        onHover: isDragging ? null : _onHover,
        onExit: isDragging ? null : (_) => _updateCursor(null),
        child: _buildHandleStack(slot, accent),
      ),
    );
  }

  // ── position computation ──────────────────────────────────────────────

  Rect _computeRect(CalendarSlot slot) {
    final scrollOffset = widget.headerScrollController?.hasClients == true
        ? widget.headerScrollController!.positions.first.pixels
        : 0.0;

    final startDay = slot.startDateTime.withoutTime;
    final startIndex =
        startDay.difference(widget.initialDate.withoutTime).inDays;
    final contentX = startIndex * widget.dayWidth;
    final viewportX = contentX - scrollOffset;

    final colWidth = widget.columnPositions[1] - widget.columnPositions[0];
    final daysSpan = slot.totalDaysSpanned;

    final naturalLeft =
        viewportX + widget.cellGapWidthPadding + widget.columnPositions[0];
    final naturalWidth =
        (daysSpan - 1) * widget.dayWidth + colWidth - widget.eventEndGap;

    // Sticky-left clamping (matching MultiDayEventsOverlay).
    final double left;
    final double width;
    if (naturalLeft < 0 && naturalLeft + naturalWidth > 0) {
      left = 0.0;
      width = (naturalLeft + naturalWidth).clamp(1.0, naturalWidth);
    } else {
      left = naturalLeft;
      width = naturalWidth;
    }

    if (naturalLeft + naturalWidth <= 0 || naturalLeft >= widget.dayWidth * 30) {
      return Rect.zero;
    }

    const rowPadding = 2.0;
    final top = rowPadding; // rowIndex handled by not stacking for now

    return Rect.fromLTRB(left, top, left + width, top + widget.eventHeight);
  }

  // ── handle stack ─────────────────────────────────────────────────────

  Widget _buildHandleStack(CalendarSlot slot, Color accent) {
    final zoneSize = widget.config.handleZoneSize;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // ── Layer 0: visual body (edge-to-edge, no gestures) ────
        Positioned.fill(
          child: IgnorePointer(
            child: SlotRenderer(
              slot: slot,
              config: widget.config,
              accentColor: accent,
              isDragging: _session != null,
            ),
          ),
        ),

        // ── Layer 1: shift zone — inset by zoneSize so it never
        // competes with the resize zones in the gesture arena. ────
        if (widget.config.enableShift)
          Positioned(
            left: widget.config.enableExtendStart ? zoneSize : 0,
            top: 0,
            right: widget.config.enableExtendEnd ? zoneSize : 0,
            bottom: 0,
            child: SlotHandleZone(
            dragMode: DragMode.shift,
            config: widget.config,
            onDragStart: (mode) => _onDragStart(mode),
            onDragUpdate: _onDragUpdate,
            onDragEnd: _onDragEnd,
            onTap: () => widget.config.onTap?.call(slot),
          ),
        ),

        // ── left handle (extend start) ─────────────────────────
        if (widget.config.enableExtendStart)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: zoneSize,
            child: SlotHandleZone(
              dragMode: DragMode.extendStart,
              config: widget.config,
              onDragStart: (mode) => _onDragStart(DragMode.extendStart),
              onDragUpdate: _onDragUpdate,
              onDragEnd: _onDragEnd,
            ),
          ),

        // ── right handle (extend end) ──────────────────────────
        if (widget.config.enableExtendEnd)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: zoneSize,
            child: SlotHandleZone(
              dragMode: DragMode.extendEnd,
              config: widget.config,
              onDragStart: (mode) => _onDragStart(DragMode.extendEnd),
              onDragUpdate: _onDragUpdate,
              onDragEnd: _onDragEnd,
            ),
          ),

        // ── handle pills ───────────────────────────────────────
        if (widget.config.showHandles && widget.config.enableExtendStart)
          Positioned(
            left: 6,
            top: 6,
            bottom: 6,
            child:IgnorePointer(
            child:  Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 4,
                height: 24,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),),

        if (widget.config.showHandles && widget.config.enableExtendEnd)
          Positioned(
            right: 6,
            top: 6,
            bottom: 6,
            child: IgnorePointer(
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                width: 4,
                height: 24,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),)
      ],
    );
  }

  // ── hover cursor ─────────────────────────────────────────────────────

  static const double _resizeZoneSize = 20.0;

  void _onHover(PointerHoverEvent event) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final localX = renderBox.globalToLocal(event.position).dx;
    final width = renderBox.size.width;

    if (!widget.config.enableExtendStart && !widget.config.enableExtendEnd) {
      _updateCursor(SystemMouseCursors.grab);
      return;
    }

    if (widget.config.enableExtendStart && localX < _resizeZoneSize) {
      _updateCursor(SystemMouseCursors.resizeLeft);
    } else if (widget.config.enableExtendEnd &&
        localX > width - _resizeZoneSize) {
      _updateCursor(SystemMouseCursors.resizeRight);
    } else {
      _updateCursor(SystemMouseCursors.grab);
    }
  }

  void _updateCursor(MouseCursor? cursor) {
    if (cursor != null && _effectiveCursor != cursor) {
      setState(() => _effectiveCursor = cursor);
    }
  }

  // ── drag lifecycle ───────────────────────────────────────────────────

  void _onDragStart(DragMode mode) {
    final slot = _slot;
    if (slot == null) return;

    widget.onDragStart?.call();

    // Idle scroll controllers.
    final hc = widget.headerScrollController;
    if (hc?.hasClients == true) hc!.jumpTo(hc.positions.first.pixels);
    final mc = widget.mainContentScrollController;
    if (mc?.hasClients == true) mc!.jumpTo(mc.positions.first.pixels);

    _session = DragSession(
      anchor: slot,
      mode: mode,
      config: widget.config,
      dayWidth: widget.dayWidth,
      heightPerMinute: 1.0,
    );

    _autoScroller?.dispose();
    _autoScroller = SlotAutoScroller(
      horizontalScrollController: widget.mainContentScrollController,
      autoScrollThreshold: widget.autoScrollThreshold,
      autoScrollMaxSpeed: widget.autoScrollMaxSpeed,
      viewportLeftInset: widget.viewportLeftInset,
      onScroll: (scrollDelta) {
        if (_session == null) return;
        _session!.addDelta(scrollDelta);
        final afterScroll = _session!.computeProposed();
        if (afterScroll != null && afterScroll != _session!.lastEmitted) {
          widget.onChanged?.call(afterScroll);
        }
      },
    );

    setState(() {
      _effectiveCursor = mode == DragMode.shift
          ? SystemMouseCursors.grabbing
          : SystemMouseCursors.resizeLeftRight;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_session == null) return;

    final updated = _session!.applyUpdate(details.delta);
    if (updated != null) {
      widget.onChanged?.call(updated);
    }

    // Feed auto-scroller with latest position and bounds.
    final bounds = _viewportBounds();
    if (bounds != null) {
      _autoScroller?.update(details.globalPosition, bounds);
    }
  }

  void _onDragEnd() {
    _session = null;
    _autoScroller?.dispose();
    _autoScroller = null;
    _updateCursor(SystemMouseCursors.basic);
    widget.onDragEnd?.call();
  }

  Rect? _viewportBounds() {
    // Reuse the same viewport detection as SlotOverlay.
    return _findViewportBounds(
      context,
      leftInset: widget.viewportLeftInset,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Viewport bounds helper (same algorithm as SlotOverlay).
// ═══════════════════════════════════════════════════════════════════════════

Rect? _findViewportBounds(BuildContext context, {double leftInset = 0}) {
  RenderObject? current = context.findRenderObject();
  if (current != null) {
    final parent = current.parent;
    current = parent is RenderObject ? parent : null;
  }
  RenderBox? best;
  double bestTop = double.negativeInfinity;

  double screenHeight;
  try {
    screenHeight = MediaQuery.sizeOf(context).height;
  } catch (_) {
    screenHeight = double.infinity;
  }

  while (current != null) {
    if (current is RenderBox && current.hasSize) {
      final size = current.size;
      if (size.width >= 200 &&
          size.height >= 200 &&
          size.height <= screenHeight) {
        try {
          final globalTop = current.localToGlobal(Offset.zero).dy;
          if (globalTop > bestTop) {
            bestTop = globalTop;
            best = current;
          }
        } catch (_) {}
      }
    }
    final parent = current.parent;
    if (parent is RenderObject) {
      current = parent;
    } else {
      break;
    }
  }

  if (best != null) {
    try {
      final globalOffset = best.localToGlobal(Offset.zero);
      return Rect.fromLTWH(
        globalOffset.dx + leftInset,
        globalOffset.dy,
        best.size.width - leftInset,
        best.size.height,
      );
    } catch (_) {}
  }

  try {
    final mediaQuery = MediaQuery.of(context);
    final padding = mediaQuery.padding;
    return Rect.fromLTWH(
      padding.left + leftInset,
      padding.top,
      mediaQuery.size.width - padding.left - padding.right - leftInset,
      mediaQuery.size.height - padding.top - padding.bottom,
    );
  } catch (_) {
    return null;
  }
}
