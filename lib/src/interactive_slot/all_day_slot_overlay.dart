import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

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
    this.viewportWidth,
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

  /// Total pixel width of the viewport (the Stack containing this
  /// overlay).  Used to detect when the slot's end extends past the
  /// visible area so borders and handles can be suppressed.
  /// When null (backward compat), end-off-screen detection is skipped.
  final double? viewportWidth;

  /// Auto-scroll parameters.
  final double autoScrollThreshold;
  final double autoScrollMaxSpeed;

  /// Called whenever the slot changes.
  final void Function(CalendarSlot? slot)? onChanged;

  /// Called when a drag begins, with the [DragMode] that was activated.
  final void Function(DragMode mode)? onDragStart;

  /// Called when a drag ends, with the [DragMode] that was active.
  /// [mode] is null if the drag was cancelled abnormally.
  final void Function(DragMode? mode)? onDragEnd;

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

    final layout = _computeLayout(slot);
    if (layout.rect.isEmpty) return const SizedBox.shrink();

    final isDragging = _session != null;
    final accent =
        widget.config.accentColor ?? Theme.of(context).colorScheme.secondary;

    return Positioned(
      left: layout.rect.left,
      top: layout.rect.top,
      width: layout.rect.width,
      height: layout.rect.height,
      child: MouseRegion(
        cursor: _effectiveCursor,
        onHover: isDragging ? null : _onHover,
        onExit: isDragging ? null : (_) => _updateCursor(null),
        child: _buildHandleStack(slot, accent, layout),
      ),
    );
  }

  // ── position computation ──────────────────────────────────────────────

  /// Computes the slot's pixel rect and off-screen status for the current
  /// scroll offset.  The rect uses sticky-left clamping (matching
  /// [MultiDayEventsOverlay]) so the start date always stays in view.
  _AllDaySlotLayout _computeLayout(CalendarSlot slot) {
    final scrollOffset = widget.headerScrollController?.hasClients == true
        ? widget.headerScrollController!.positions.first.pixels
        : 0.0;

    final startDay = slot.startDateTime.withoutTime;
    final startIndex = startDay
        .difference(widget.initialDate.withoutTime)
        .inDays;
    final contentX = startIndex * widget.dayWidth;
    final viewportX = contentX - scrollOffset;

    final colWidth = widget.columnPositions[1] - widget.columnPositions[0];
    final daysSpan = slot.totalDaysSpanned;

    final naturalLeft =
        viewportX + widget.cellGapWidthPadding + widget.columnPositions[0];
    final naturalWidth =
        (daysSpan - 1) * widget.dayWidth + colWidth - widget.eventEndGap;

    // Completely off-screen? Return empty.
    if (naturalLeft + naturalWidth <= 0 ||
        naturalLeft >= widget.dayWidth * 30) {
      return _AllDaySlotLayout.zero;
    }

    // Start is off-screen when the natural left edge is before the
    // viewport (sticky-left will clamp to 0).
    final isStartOffScreen = naturalLeft < 0 && naturalLeft + naturalWidth > 0;

    // Sticky-left clamping.
    final double left;
    final double width;
    if (isStartOffScreen) {
      left = 0.0;
      width = (naturalLeft + naturalWidth).clamp(1.0, naturalWidth);
    } else {
      left = naturalLeft;
      width = naturalWidth;
    }

    // End is off-screen independently of the start: it happens when the
    // natural right edge extends past the viewport's right edge.
    // Use the explicit viewportWidth parameter when provided, otherwise
    // derive it from the Stack ancestor's RenderBox size.
    final bool isEndOffScreen;
    final effectiveViewportWidth =
        widget.viewportWidth ?? _stackWidthFromContext(context);
    if (effectiveViewportWidth != null) {
      isEndOffScreen = naturalLeft + naturalWidth > effectiveViewportWidth;
    } else {
      // Last-resort fallback: detect via width truncation from
      // sticky-left clamping only.
      isEndOffScreen = width < naturalWidth;
    }

    const rowPadding = 2.0;
    final top = rowPadding;

    return _AllDaySlotLayout(
      rect: Rect.fromLTRB(left, top, left + width, top + widget.eventHeight),
      isStartOffScreen: isStartOffScreen,
      isEndOffScreen: isEndOffScreen,
    );
  }

  // ── handle stack ─────────────────────────────────────────────────────

  Widget _buildHandleStack(
    CalendarSlot slot,
    Color accent,
    _AllDaySlotLayout layout,
  ) {
    final zoneSize = widget.config.handleZoneSize;
    final isStartOff = layout.isStartOffScreen;
    final isEndOff = layout.isEndOffScreen;
    final activeMode = _session?.mode;

    // Hide handles when their edge is off-screen — the event is "ongoing"
    // and should not show resize affordances on the clipped side. Keep the
    // active handle mounted, though, so auto-scroll drags receive their
    // normal pointer end/cancel lifecycle.
    final showLeftHandle =
        widget.config.enableResize &&
        widget.config.enableResizeStart &&
        (!isStartOff || activeMode == DragMode.extendStart);
    final showRightHandle =
        widget.config.enableResize &&
        widget.config.enableResizeEnd &&
        (!isEndOff || activeMode == DragMode.extendEnd);

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
              hideLeftBorder: isStartOff,
              hideRightBorder: isEndOff,
              hideLeftHandle: !showLeftHandle,
              hideRightHandle: !showRightHandle,
            ),
          ),
        ),

        // ── Layer 1: shift zone — inset by zoneSize so it never
        // competes with the resize zones in the gesture arena. ────
        if (widget.config.enableShift)
          Positioned(
            left: showLeftHandle ? zoneSize : 0,
            top: 0,
            right: showRightHandle ? zoneSize : 0,
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
        if (showLeftHandle)
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
        if (showRightHandle)
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
        if (showLeftHandle && widget.config.showHandles)
          Positioned(
            left: 6,
            top: 6,
            bottom: 6,
            child: IgnorePointer(
              child: Align(
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
            ),
          ),

        if (showRightHandle && widget.config.showHandles)
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
            ),
          ),
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

    if (!widget.config.enableResizeStart && !widget.config.enableResizeEnd) {
      _updateCursor(SystemMouseCursors.grab);
      return;
    }

    final slot = _slot;
    if (slot != null) {
      final layout = _computeLayout(slot);
      final showLeft =
          widget.config.enableResizeStart && !layout.isStartOffScreen;
      final showRight = widget.config.enableResizeEnd && !layout.isEndOffScreen;

      if (showLeft && localX < _resizeZoneSize) {
        _updateCursor(SystemMouseCursors.resizeLeft);
        return;
      }
      if (showRight && localX > width - _resizeZoneSize) {
        _updateCursor(SystemMouseCursors.resizeRight);
        return;
      }
    }

    _updateCursor(SystemMouseCursors.grab);
  }

  void _updateCursor(MouseCursor? cursor) {
    if (cursor == null || _effectiveCursor == cursor) return;

    if (!mounted) {
      _effectiveCursor = cursor;
      return;
    }

    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      setState(() => _effectiveCursor = cursor);
    } else {
      _effectiveCursor = cursor;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  // ── drag lifecycle ───────────────────────────────────────────────────

  void _onDragStart(DragMode mode) {
    final slot = _slot;
    if (slot == null) return;

    widget.onDragStart?.call(mode);
    widget.config.onDragStart?.call(mode);

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
    final mode = _session?.mode;
    _session = null;
    _autoScroller?.dispose();
    _autoScroller = null;
    _updateCursor(SystemMouseCursors.basic);
    widget.onDragEnd?.call(mode);
    widget.config.onDragEnd?.call(mode);
  }

  Rect? _viewportBounds() {
    // Reuse the same viewport detection as SlotOverlay.
    return _findViewportBounds(context, leftInset: widget.viewportLeftInset);
  }

  /// Walks up the render tree from [context] to find the nearest Stack
  /// ancestor's RenderBox and returns its width.  Used as a fallback for
  /// [viewportWidth] to detect when the slot's end is off-screen right.
  static double? _stackWidthFromContext(BuildContext context) {
    RenderObject? current = context.findRenderObject();
    // Step past our own RenderBox (which is the Positioned wrapper).
    if (current != null) {
      current = current.parent;
    }
    // Walk up until we find a RenderBox whose corresponding widget is a
    // Stack (or until we run out of ancestors).
    while (current != null) {
      if (current is RenderBox && current.hasSize) {
        return current.size.width;
      }
      current = current.parent;
    }
    return null;
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

// ═══════════════════════════════════════════════════════════════════════════
// Layout helper — bundles the computed rect with off-screen status flags.
// ═══════════════════════════════════════════════════════════════════════════

class _AllDaySlotLayout {
  const _AllDaySlotLayout({
    required this.rect,
    required this.isStartOffScreen,
    required this.isEndOffScreen,
  });

  static const _AllDaySlotLayout zero = _AllDaySlotLayout(
    rect: Rect.zero,
    isStartOffScreen: false,
    isEndOffScreen: false,
  );

  final Rect rect;

  /// True when the slot's start day is before the visible viewport
  /// (sticky-left clamping is active).
  final bool isStartOffScreen;

  /// True when the slot's end day is beyond the visible viewport
  /// (the right side has been clipped).
  final bool isEndOffScreen;
}
