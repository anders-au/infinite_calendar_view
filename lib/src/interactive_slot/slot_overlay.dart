import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../utils/extension.dart';
import '../utils/planner_time_mapper.dart';
import 'handles/slot_handle.dart';
import 'slot_config.dart';
import 'slot_controller.dart';
import 'slot_renderer.dart';
import 'slot_selection.dart';

/// Positions an interactive slot in the planner's [Stack] and manages
/// its drag/resize lifecycle.
///
/// Listens to [slotNotifier] for the current [CalendarSlot] and renders
/// it at the correct pixel position computed from the horizontal scroll
/// offset, column layout, and time mapper.
///
/// When the user drags a handle or the body, a [DragSession] is created
/// and the slot model is updated via [onChanged].
class SlotOverlay extends StatefulWidget {
  const SlotOverlay({
    super.key,
    required this.slotNotifier,
    required this.config,
    required this.timeMapper,
    required this.dayWidth,
    required this.plannerHeight,
    required this.dayTopPadding,
    required this.dayBottomPadding,
    required this.cellGapWidthPadding,
    required this.columnPositions,
    required this.initialDate,
    this.scrollController,
    this.verticalScrollController,
    this.viewportLeftInset = 0,
    this.viewportRightInset = 0,
    this.autoScrollThreshold = 40.0,
    this.autoScrollMaxSpeed = 8.0,
    this.onChanged,
    this.onDragStart,
    this.onDragEnd,
  });

  /// Notifier holding the current [CalendarSlot].
  final ValueNotifier<CalendarSlot?> slotNotifier;

  /// Interaction configuration.
  final SlotInteractionConfig config;

  /// Time-to-pixel mapper.
  final PlannerTimeMapper timeMapper;

  /// Width of one day column in logical pixels.
  final double dayWidth;

  /// Full height of the planner (time grid area).
  final double plannerHeight;

  /// Top padding applied by the planner to the time-grid area.
  final double dayTopPadding;

  /// Bottom padding applied by the planner.
  final double dayBottomPadding;

  /// Half the cell-gap width.
  final double cellGapWidthPadding;

  /// Per-column positions `[startOffset, endOffset]` within the padded day.
  final List<double> columnPositions;

  /// The planner's initial date (used for day-index calculations).
  final DateTime initialDate;

  /// Horizontal scroll controller for auto-scroll.
  final ScrollController? scrollController;

  /// Vertical scroll controller for auto-scroll.
  final ScrollController? verticalScrollController;

  /// Insets for auto-scroll edge detection.
  final double viewportLeftInset;
  final double viewportRightInset;

  /// Auto-scroll parameters.
  final double autoScrollThreshold;
  final double autoScrollMaxSpeed;

  /// Called whenever the slot changes (drag update).
  final void Function(CalendarSlot? slot)? onChanged;

  /// Called when a drag begins, with the [DragMode] that was activated.
  final void Function(DragMode mode)? onDragStart;

  /// Called when a drag ends.
  ///
  /// [keepInView] is the day that should remain visible:
  /// * extendEnd → the end date
  /// * extendStart → the start date
  /// * shift → the new start date
  /// * null → no reconciliation needed
  ///
  /// [mode] is the [DragMode] that was active during the drag,
  /// or null if the drag was cancelled abnormally.
  final void Function(DateTime? keepInView, DragMode? mode)? onDragEnd;

  @override
  State<SlotOverlay> createState() => _SlotOverlayState();
}

class _SlotOverlayState extends State<SlotOverlay> {
  DragSession? _session;
  SlotAutoScroller? _autoScroller;
  MouseCursor _effectiveCursor = SystemMouseCursors.basic;

  CalendarSlot? get _slot => widget.slotNotifier.value;

  @override
  void initState() {
    super.initState();
    // Rebuild when the notifier emits a new slot value.
    widget.slotNotifier.addListener(_onSlotChanged);
    // Rebuild when the horizontal scroll offset changes so the slot
    // stays pinned to the correct day column.
    widget.scrollController?.addListener(_onScrollChanged);
  }

  @override
  void didUpdateWidget(covariant SlotOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slotNotifier != widget.slotNotifier) {
      oldWidget.slotNotifier.removeListener(_onSlotChanged);
      widget.slotNotifier.addListener(_onSlotChanged);
    }
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController?.removeListener(_onScrollChanged);
      widget.scrollController?.addListener(_onScrollChanged);
    }
  }

  void _onSlotChanged() {
    if (mounted) setState(() {});
  }

  void _onScrollChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.slotNotifier.removeListener(_onSlotChanged);
    widget.scrollController?.removeListener(_onScrollChanged);
    _autoScroller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slot = _slot;
    if (slot == null) return const SizedBox.shrink();
    if (slot.isAllDay) return const SizedBox.shrink();

    final isDragging = _session != null;
    final accent = widget.config.accentColor ?? Theme.of(context).colorScheme.secondary;
    return _buildColumnLayout(slot, accent, isDragging);
  }

  /// Unified Row-based column layout for **all** timed slots (1..N days).
  ///
  /// **Two-layer architecture:**
  /// - **Render layer** — visual elements (SegmentBody, handle pills).
  ///   Uses the live [slot] values so the slot follows the finger reactively.
  /// - **Gesture layer** — interactive zones (shift, resize handles).
  ///   During a drag, uses the immutable [DragSession.anchor] so the
  ///   widget tree never restructures and gesture state is preserved.
  ///
  /// This single code path replaces the old single-day / multi-day split.
  Widget _buildColumnLayout(CalendarSlot slot, Color accent, bool isDragging) {
    final scrollOffset = widget.scrollController?.hasClients == true
        ? widget.scrollController!.positions.first.pixels
        : 0.0;

    // ── Render-layer values (reactive — follow the live slot) ─────
    final rStartDay = slot.startDateTime.withoutTime;
    final rStartDayIndex = rStartDay.difference(widget.initialDate.withoutTime).inDays;
    final rStartMinute = slot.startDateTime.totalMinutes.toDouble();
    final rEndMinuteAbs = (rStartMinute + slot.durationInMinutes).toDouble();
    final rTotalDays = slot.totalDaysSpanned;

    // ── Gesture-layer values (stable during drag) ─────────────────
    final anchor = _session?.anchor;
    final gTotalDays = anchor?.totalDaysSpanned ?? rTotalDays;
    final gStartMinute = (anchor?.startDateTime.totalMinutes ?? rStartMinute).toDouble();
    final gEndMinuteAbs = (gStartMinute + (anchor?.durationInMinutes ?? slot.durationInMinutes)).toDouble();

    final dayWidth = widget.dayWidth;
    final dayHeight = widget.timeMapper.totalDayHeight();
    final gapH = widget.timeMapper.cellGapHeight;
    final colWidth = widget.columnPositions[1] - widget.columnPositions[0];
    final pad = widget.cellGapWidthPadding;
    final paddedWidth = dayWidth - 2 * pad;
    // Left/right padding so every column's segment matches colWidth.
    final segPadL = pad + widget.columnPositions[0];
    final segPadR = pad + paddedWidth - widget.columnPositions[1];
    final zoneSize = widget.config.handleZoneSize;

    // ── Build day columns (RENDER layer — uses live slot) ────────
    final List<Widget> columns = [];

    for (int d = 0; d < rTotalDays; d++) {
      final isFirst = d == 0;
      final isLast = d == rTotalDays - 1;

      final colKey = isFirst && isLast ? 'singleSlotColumn'
          : isFirst ? 'startSlotColumn'
          : isLast ? 'endSlotColumn'
          : 'midSlotColumn$d';

      final double segTop;
      final double segHeight;

      if (isFirst && isLast) {
        segTop = widget.timeMapper.minuteToY(rStartMinute);
        double raw = widget.timeMapper.minuteToY(rEndMinuteAbs);
        if (gapH > 0 && rEndMinuteAbs > 0 &&
            rEndMinuteAbs < PlannerTimeMapper.minutesPerDay &&
            rEndMinuteAbs % PlannerTimeMapper.minutesPerHour == 0) raw -= gapH;
        segHeight = (raw - segTop).clamp(0.0, dayHeight);
      } else if (isFirst) {
        segTop = widget.timeMapper.minuteToY(rStartMinute);
        segHeight = (dayHeight - segTop).clamp(0.0, dayHeight);
      } else if (isLast) {
        final intra = rEndMinuteAbs -
            (rTotalDays - 1) * PlannerTimeMapper.minutesPerDay;
        double raw = widget.timeMapper.minuteToY(intra);
        if (gapH > 0 && intra > 0 &&
            intra < PlannerTimeMapper.minutesPerDay &&
            intra % PlannerTimeMapper.minutesPerHour == 0) raw -= gapH;
        segTop = 0;
        segHeight = raw.clamp(0.0, dayHeight);
      } else {
        segTop = 0;
        segHeight = dayHeight;
      }

      // ── Build column children (visual only, ignore pointer) ──
      final List<Widget> colChildren = [];

      if (segHeight > 0) {
        colChildren.add(Positioned(
          top: segTop,
          left: segPadL,
          right: segPadR,
          height: segHeight,
          child: SegmentBody(
            accent: accent,
            borderRadius: widget.config.slotBorderRadius,
            hideTopBorder: !isFirst,
            hideBottomBorder: !isLast,
            isDragging: isDragging,
            padTop: isFirst ? zoneSize : 0,
            padBottom: isLast ? zoneSize : 0,
            showStartLabel: isFirst && widget.config.showDefaultSlotText,
            showEndLabel: isLast && widget.config.showDefaultSlotText,
            startTime: slot.startDateTime,
            endTime: slot.endDateTime,
            use24HourFormat: widget.config.use24HourFormat,
          ),
        ));
      }

      columns.add(
        IgnorePointer(
          child: SizedBox(
            key: ValueKey(colKey),
            width: dayWidth,
            child: Stack(clipBehavior: Clip.none, children: colChildren),
          ),
        ),
      );
    }

    if (columns.isEmpty) return const SizedBox.shrink();

    // ── Viewport position (reactive — follows live slot) ──────────
    final viewportX = rStartDayIndex * dayWidth - scrollOffset;
    final left = viewportX;
    final totalWidth = rTotalDays * dayWidth;

    // ── Build outer Stack children ────────────────────────────────
    final List<Widget> outerChildren = [];
    // Visual columns — wrapped in IgnorePointer so they never absorb
    // hit tests.  Only the interactive zones below receive events.
    outerChildren.add(IgnorePointer(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch,
         textDirection: TextDirection.ltr, children: columns)));

    // ── Shift zones (GESTURE layer — stable during drag) ─────────
    // Uses anchor values so the widget tree never restructures.
    if (widget.config.enableShift) {
      for (int d = 0; d < gTotalDays; d++) {
        final gIsFirst = d == 0;
        final gIsLast = d == gTotalDays - 1;

        final double gSegTop;
        final double gSegHeight;

        if (gIsFirst && gIsLast) {
          gSegTop = widget.timeMapper.minuteToY(gStartMinute);
          double raw = widget.timeMapper.minuteToY(gEndMinuteAbs);
          if (gapH > 0 && gEndMinuteAbs > 0 &&
              gEndMinuteAbs < PlannerTimeMapper.minutesPerDay &&
              gEndMinuteAbs % PlannerTimeMapper.minutesPerHour == 0) raw -= gapH;
          gSegHeight = (raw - gSegTop).clamp(0.0, dayHeight);
        } else if (gIsFirst) {
          gSegTop = widget.timeMapper.minuteToY(gStartMinute);
          gSegHeight = (dayHeight - gSegTop).clamp(0.0, dayHeight);
        } else if (gIsLast) {
          final intra = gEndMinuteAbs -
              (gTotalDays - 1) * PlannerTimeMapper.minutesPerDay;
          double raw = widget.timeMapper.minuteToY(intra);
          if (gapH > 0 && intra > 0 &&
              intra < PlannerTimeMapper.minutesPerDay &&
              intra % PlannerTimeMapper.minutesPerHour == 0) raw -= gapH;
          gSegTop = 0;
          gSegHeight = raw.clamp(0.0, dayHeight);
        } else {
          gSegTop = 0;
          gSegHeight = dayHeight;
        }

        if (gSegHeight > 0) {
          outerChildren.add(Positioned(
            left: d * dayWidth + segPadL,
            top: gSegTop,
            width: colWidth,
            height: gSegHeight,
            child: SlotHandleZone(
              key: ValueKey('shiftZone$d'),
              dragMode: DragMode.shift,
              config: widget.config,
              onDragStart: (m) => _onDragStart(m),
              onDragUpdate: _onDragUpdate,
              onDragEnd: _onDragEnd,
              onTap: () => widget.config.onTap?.call(slot),
            ),
          ));
        }
      }
    }

    // Start handle — always at column 0 (reactive position).
    if (widget.config.enableResize && widget.config.enableExtendStart && rTotalDays > 0) {
      final topY = widget.timeMapper.minuteToY(rStartMinute);
      outerChildren.add(Positioned(
        left: segPadL, top: topY, width: colWidth, height: zoneSize,
        child: SlotHandleZone(
          key: const ValueKey('startHandle'),
          dragMode: DragMode.extendStart, config: widget.config,
          onDragStart: (m) => _onDragStart(m), onDragUpdate: _onDragUpdate,
          onDragEnd: _onDragEnd),
      ));
      if (widget.config.showHandles) {
        outerChildren.add(Positioned(
          left: segPadL + 6, top: topY + 6, width: colWidth - 12, height: zoneSize - 6,
          child: IgnorePointer(child: Align(alignment: Alignment.topCenter,
            child: HandlePill(color: accent, width: 36, height: 4))),
        ));
      }
    }

    // End handle — always at the last column (reactive position).
    if (widget.config.enableResize && widget.config.enableExtendEnd && rTotalDays > 0) {
      final intra = rEndMinuteAbs - (rTotalDays - 1) * PlannerTimeMapper.minutesPerDay;
      double raw = widget.timeMapper.minuteToY(intra);
      if (gapH > 0 && intra > 0 && intra < PlannerTimeMapper.minutesPerDay &&
          intra % PlannerTimeMapper.minutesPerHour == 0) raw -= gapH;
      final endY = raw.clamp(0.0, dayHeight);
      final endL = (rTotalDays - 1) * dayWidth + segPadL;
      outerChildren.add(Positioned(
        left: endL, top: endY - zoneSize, width: colWidth, height: zoneSize,
        child: SlotHandleZone(
          key: const ValueKey('endHandle'),
          dragMode: DragMode.extendEnd, config: widget.config,
          onDragStart: (m) => _onDragStart(DragMode.extendEnd),
          onDragUpdate: _onDragUpdate, onDragEnd: _onDragEnd),
      ));
      if (widget.config.showHandles) {
        outerChildren.add(Positioned(
          left: endL + 6, top: endY - zoneSize + 2, width: colWidth - 12, height: zoneSize - 6,
          child: IgnorePointer(child: Align(alignment: Alignment.bottomCenter,
            child: HandlePill(color: accent, width: 36, height: 4))),
        ));
      }
    }

    return Positioned(
      left: left,
      top: widget.dayTopPadding,
      width: totalWidth,
      height: dayHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: outerChildren,
      ),
    );
  }

  void _updateCursor(MouseCursor? cursor) {
    if (cursor != null && _effectiveCursor != cursor && mounted) {
      setState(() => _effectiveCursor = cursor);
    }
  }

  // ── drag lifecycle ───────────────────────────────────────────────────

  void _onDragStart(DragMode mode) {
    final slot = _slot;
    if (slot == null) return;

    if (debugSlotDrag) {
      debugPrint('[SlotOverlay] _onDragStart  '
          'mode=$mode  '
          'start=${slot.startDateTime.toIso8601String()}  '
          'end=${slot.endDateTime.toIso8601String()}  '
          'days=${slot.totalDaysSpanned}  '
          'dur=${slot.durationInMinutes}min');
    }

    widget.onDragStart?.call(mode);
    widget.config.onDragStart?.call(mode);

    // Idle the scroll controllers so auto-scroll jumpTo works cleanly.
    final sc = widget.scrollController;
    if (sc?.hasClients == true) sc!.jumpTo(sc.positions.first.pixels);
    final vc = widget.verticalScrollController;
    if (vc?.hasClients == true) vc!.jumpTo(vc.positions.first.pixels);

    _session = DragSession(
      anchor: slot,
      mode: mode,
      config: widget.config,
      dayWidth: widget.dayWidth,
      heightPerMinute: widget.timeMapper.heightPerMinute,
    );

    _autoScroller?.dispose();
    _autoScroller = SlotAutoScroller(
      verticalScrollController: widget.verticalScrollController,
      horizontalScrollController: widget.scrollController,
      autoScrollThreshold: widget.autoScrollThreshold,
      autoScrollMaxSpeed: widget.autoScrollMaxSpeed,
      viewportLeftInset: widget.viewportLeftInset,
      viewportRightInset: widget.viewportRightInset,
      onScroll: (delta) {
        if (_session == null) return;
        _session!.addDelta(delta);
        final s = _session!.computeProposed();
        if (s != null && s != _session!.lastEmitted) {
          widget.onChanged?.call(s);
        }
      },
    );

    setState(() {
      _effectiveCursor = mode == DragMode.shift ? SystemMouseCursors.grabbing : SystemMouseCursors.resizeUpDown;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_session == null) return;

    _session!.applyUpdate(details.delta);
    final updated = _session!.lastEmitted;
    if (updated != null) {
      widget.onChanged?.call(updated);
    }

    // Keep auto-scroll alive — the timer fires independently.
    final bounds = _viewportBounds();
    if (bounds != null) {
      _autoScroller?.update(details.globalPosition, bounds);
    }
  }

  void _onDragEnd() {
    final mode = _session?.mode;
    DateTime? keepInView;
    if (mode != null && _slot != null) {
      keepInView = switch (mode) {
        DragMode.extendEnd => _slot!.endDateTime,
        DragMode.extendStart => _slot!.startDateTime,
        DragMode.shift => _slot!.startDateTime,
      };
    }
    _session = null;
    _autoScroller?.dispose();
    _autoScroller = null;
    _updateCursor(SystemMouseCursors.basic);
    widget.onDragEnd?.call(keepInView, mode);
    widget.config.onDragEnd?.call(mode);
  }

  Rect? _viewportBounds() {
    return _viewportBoundsOf(
      context,
      leftInset: widget.viewportLeftInset,
      rightInset: widget.viewportRightInset,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Viewport bounds helper.
// ═══════════════════════════════════════════════════════════════════════════

/// Walks up the render tree from [context] to find the planner viewport
/// [RenderBox] and returns its global bounds, excluding the given insets
/// (typically the time-indicator column width).
Rect? _viewportBoundsOf(BuildContext context, {double leftInset = 0, double rightInset = 0}) {
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
      if (size.width >= 200 && size.height >= 200 && size.height <= screenHeight) {
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
        best.size.width - leftInset - rightInset,
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
      mediaQuery.size.width - padding.left - padding.right - leftInset - rightInset,
      mediaQuery.size.height - padding.top - padding.bottom,
    );
  } catch (_) {
    return null;
  }
}
