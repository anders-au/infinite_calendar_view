import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:infinite_calendar_view/infinite_calendar_view.dart';

import '../../utils/planner_time_mapper.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Custom immediate-drag gesture recognizer.
//
// Unlike LongPressGestureRecognizer (which has a built-in delay) or
// PanGestureRecognizer (which loses to scroll in a gesture arena), this
// recognizer enters the arena on pointer-down and resolves to *accepted*
// as soon as the pointer moves past the configured drag threshold.  This
// gives zero-delay drags that always win over the planner's scroll
// recognizers while still allowing taps (pointer-up before threshold).
// ═══════════════════════════════════════════════════════════════════════════

class _SlotDragRecognizer extends OneSequenceGestureRecognizer {
  _SlotDragRecognizer({required this.dragThreshold, this.dragMode, required this.onStart, required this.onUpdate, required this.onEnd, required this.onTap});

  final double dragThreshold;

  /// If non-null, the drag mode is pre-determined by the creator (e.g.
  /// multi-day handle zones).  If null, the [InteractiveSlotState] will
  /// determine the mode from the pointer position on the first update.
  final _DragMode? dragMode;

  final void Function(_DragMode? mode) onStart;
  final void Function(DragUpdateDetails) onUpdate;
  final VoidCallback onEnd;
  final VoidCallback onTap;

  Offset? _startGlobal;
  bool _dragStarted = false;
  int? _pointer;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (_pointer != null) {
      // A new pointer arrived while the previous one is still tracked.
      // This happens when the system steals the pointer (e.g., Android
      // edge gesture) without delivering a cancel event.  Cancel the
      // old drag immediately so the auto-scroll timer stops before it
      // can interfere with the new gesture.
      if (_dragStarted) {
        onEnd();
      }
      stopTrackingPointer(_pointer!);
      _pointer = null;
      _startGlobal = null;
      _dragStarted = false;
    }
    startTrackingPointer(event.pointer);
    _pointer = event.pointer;
    _startGlobal = event.position;
    _dragStarted = false;
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _pointer) return;

    if (event is PointerMoveEvent) {
      if (_startGlobal == null) return;
      final delta = event.position - _startGlobal!;
      if (!_dragStarted) {
        if (delta.distance < dragThreshold) return;
        _dragStarted = true;
        resolve(GestureDisposition.accepted);
        onStart(dragMode);
      }
      onUpdate(
        DragUpdateDetails(
          sourceTimeStamp: event.timeStamp,
          delta: event.localDelta,
          globalPosition: event.position,
          localPosition: event.localPosition,
        ),
      );
    } else if (event is PointerUpEvent) {
      if (!_dragStarted) {
        onTap();
        resolve(GestureDisposition.accepted);
      } else {
        onEnd();
      }
      _finish(event.pointer);
    } else if (event is PointerCancelEvent) {
      if (_dragStarted) {
        onEnd();
      }
      _finish(event.pointer);
    }
  }

  @override
  void acceptGesture(int pointer) {}

  @override
  void rejectGesture(int pointer) {
    if (_pointer == pointer) {
      if (_dragStarted) {
        onEnd();
      }
      _finish(pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    // The framework stopped tracking all pointers for this recognizer.
    // This can happen when the engine removes the pointer (e.g., Android
    // edge gesture) without sending a PointerCancelEvent. Clean up.
    if (_dragStarted) {
      onEnd();
    }
    _pointer = null;
    _startGlobal = null;
    _dragStarted = false;
  }

  void _finish(int pointer) {
    if (_pointer == pointer) {
      stopTrackingPointer(pointer);
      _pointer = null;
      _startGlobal = null;
      _dragStarted = false;
    }
  }

  @override
  String get debugDescription => '_SlotDragRecognizer';
}

// ═══════════════════════════════════════════════════════════════════════════
// Drag mode enum
// ═══════════════════════════════════════════════════════════════════════════

enum _DragMode { shift, resizeTop, resizeBottom }

// ═══════════════════════════════════════════════════════════════════════════
// Immutable snapshot of the slot state taken at drag start.
//
// A nullable `_SlotDragSession?` field replaces the previous five
// scattered mutable fields (`_dragMode`, `_dragCommitted`,
// `_snapStartDate`, `_snapEndDate`, `_snapDurationMin`).
// `_session == null` means no drag is in progress; a non-null session
// means the drag is committed and its mode/time anchors are immutable.
// ═══════════════════════════════════════════════════════════════════════════

class _SlotDragSession {
  const _SlotDragSession({
    required this.mode,
    required this.snapStartDate,
    required this.snapEndDate,
    required this.snapDurationMin,
    required this.snapTotalDays,
  });

  final _DragMode mode;
  final DateTime snapStartDate;
  final DateTime snapEndDate;
  final int snapDurationMin;
  final int snapTotalDays;
}

// ═══════════════════════════════════════════════════════════════════════════
// InteractiveSlot widget
// ═══════════════════════════════════════════════════════════════════════════

class InteractiveSlot extends StatefulWidget {
  const InteractiveSlot({
    super.key,
    required this.slot,
    required this.dayWidth,
    required this.dayParam,
    required this.columnsParam,
    required this.heightPerMinute,
    this.plannerTimeMapper,
    required this.onChanged,
    this.verticalScrollController,
    this.horizontalScrollController,
    this.autoScrollThreshold = 40.0,
    this.autoScrollMaxSpeed = 8.0,
    this.viewportLeftInset = 0,
    this.viewportRightInset = 0,
    this.cellGapWidthPadding = 0,
    this.onDragStart,
    this.onDragEnd,
  });

  /// Half the [EventsPlanner.cellGapWidth], used as horizontal padding
  /// on each side of every day column.  Multi-day slots use this to
  /// constrain per-day segments to the actual column content area so
  /// they do not bleed into the gap between day columns.
  final double cellGapWidthPadding;

  final CalendarSlot slot;
  final double dayWidth;
  final DayParam dayParam;
  final ColumnsParam columnsParam;
  final double heightPerMinute;
  final PlannerTimeMapper? plannerTimeMapper;
  final void Function(CalendarSlot? updatedSlot) onChanged;

  /// When set, the planner's vertical scroll controller — used for
  /// edge-triggered auto-scrolling while dragging or resizing the slot.
  final ScrollController? verticalScrollController;

  /// When set, the planner's horizontal scroll controller — used for
  /// edge-triggered auto-scrolling while dragging the slot.
  final ScrollController? horizontalScrollController;

  /// Distance in logical pixels from the viewport edge at which
  /// auto-scrolling begins. Set to 0 to disable auto-scrolling.
  final double autoScrollThreshold;

  /// Horizontal insets to exclude from auto-scroll edge detection.
  /// Typically set to the time-indicators column width so that
  /// auto-scroll triggers when the pointer reaches the planner
  /// content edge, not the far edge of the time column.
  final double viewportLeftInset;
  final double viewportRightInset;

  /// Maximum scroll speed in logical pixels per tick (~60 fps) when
  /// the pointer is at (or past) the viewport edge.
  final double autoScrollMaxSpeed;

  /// Called when a drag gesture begins on this slot.
  final VoidCallback? onDragStart;

  /// Called when a drag gesture ends (pointer up or cancelled).
  /// [isResize] is true when the drag was a resize operation (top or
  /// bottom handle) and false when it was a positional shift.
  final void Function({required bool isResize})? onDragEnd;

  PlannerTimeMapper get timeMapper => plannerTimeMapper ?? PlannerTimeMapper(heightPerMinute: heightPerMinute);

  @override
  State<InteractiveSlot> createState() => InteractiveSlotState();
}

class InteractiveSlotState extends State<InteractiveSlot> with WidgetsBindingObserver {
  // ── drag state ──────────────────────────────────────────────────────
  /// Null when no drag is active; non-null once the drag is committed
  /// (first move past threshold).  The session's [mode] and snapshot
  /// times are immutable for the lifetime of the drag.
  _SlotDragSession? _session;

  // ── debug logging ───────────────────────────────────────────────────
  static bool _debugDrag = true;
  void _log(String msg) {
    if (_debugDrag) debugPrint('[InteractiveSlot] $msg');
  }

  /// Accumulated pixel delta since drag start (or last auto-scroll
  /// compensation).  Independent of widget repositioning.
  Offset _accumulatedDelta = Offset.zero;

  /// Carries the drag mode from [_onDragStart] to the first
  /// [_onDragUpdate] call where the session is created.  Cleared
  /// in [_resetDrag].
  _DragMode? _preSetMode;

  /// Last global position during a long-press drag, used to compute
  /// per-frame delta since [LongPressMoveUpdateDetails] does not
  /// carry a delta field.
  Offset _lastLongPressGlobalPosition = Offset.zero;

  // ── cursor state ────────────────────────────────────────────────────
  MouseCursor _effectiveCursor = SystemMouseCursors.basic;
  bool _isDragging = false;

  // ── auto-scroll state ───────────────────────────────────────────────
  Timer? _autoScrollTimer;
  Offset _lastGlobalPosition = Offset.zero;
  DateTime _lastDragUpdateTime = DateTime.now();

  /// If no drag-update event arrives within this window the auto-scroll
  /// timer will stop itself.  This recovers from pointer-steal scenarios
  /// (e.g., Android edge gesture) where no cancel/reject event is
  /// delivered.
  static const Duration _autoScrollStaleTimeout = Duration(milliseconds: 250);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopAutoScroll();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _log('App lifecycle: $state — forcing drag reset');
      _resetDrag();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final param = widget.dayParam.slotInteractionConfig;
    final accent = param.accentColor ?? theme.colorScheme.secondary;
    final borderRadius = param.slotBorderRadius;
    final slot = widget.slot;
    // Freeze the multi-day layout during a drag so the widget tree
    // doesn't switch between single-day and multi-day rendering.
    // During a drag ALL positional values come from the session
    // snapshot + accumulated delta, never from widget.slot — this
    // keeps the gesture recognizer alive even when the parent
    // rebuilds with a different key (e.g. after crossing midnight).
    final snapTotalDays = _session?.snapTotalDays ?? slot.totalDaysSpanned;
    final isMultiDay = snapTotalDays > 1;

    // ── Multi-day: build content without a slot-wide drag recognizer ─
    // Only the handle zones and a long-press body zone get their own
    // drag targets; the rest of the slot is transparent to pointer
    // events so scroll views work.
    if (isMultiDay) {
      return MouseRegion(
        opaque: false, // transparent to hit testing; hover still fires
        cursor: _effectiveCursor,
        onHover: _isDragging ? null : _onHover,
        onExit: _isDragging ? null : (_) => _updateCursor(null),
        child: Stack(clipBehavior: Clip.none, children: _buildMultiDayBody(theme, accent, borderRadius)),
      );
    }

    // ── Single-day: zone-based layout ──────────────────────────────
    // The body uses a long-press gesture (shift via long-press+drag)
    // so quick flings pass through to the calendar scroll views.
    // Resize handles use immediate drag (_SlotDragRecognizer).
    final canDrag = param.enableShift;
    final hasResize = param.enableResize;
    final zoneSize = param.handleZoneSize;
    return MouseRegion(
      cursor: _effectiveCursor,
      onHover: _isDragging ? null : _onHover,
      onExit: _isDragging ? null : (_) => _updateCursor(null),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerCancel: _isDragging ? (_) => _onPointerCancelled() : null,
        onPointerUp: _isDragging ? (_) {} : null,
        onPointerMove: _isDragging ? (_) {} : null,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            boxShadow: _session != null
                ? [BoxShadow(color: accent.withAlpha(70), blurRadius: 10, offset: const Offset(0, 3))]
                : [BoxShadow(color: accent.withAlpha(25), blurRadius: 4, offset: const Offset(0, 1))],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // ── Layer 0: content + body shift zone (long-press drag) ─
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => param.onTap?.call(slot),
                  onLongPressStart: canDrag ? _onLongPressStart : null,
                  onLongPressMoveUpdate: canDrag ? _onLongPressMoveUpdate : null,
                  onLongPressEnd: canDrag ? (_) => _onLongPressEnd() : null,
                  child: param.slotContentBuilder?.call(slot) ?? _buildDefaultContent(theme, accent, borderRadius),
                ),
              ),

              // ── Layer 1: top resize handle (immediate drag) ──────
              if (hasResize)
                Positioned(
                  top: 0, left: 0, right: 0, height: zoneSize,
                  child: Builder(
                    builder: (ctx) {
                      final gestures = <Type, GestureRecognizerFactory>{
                        _SlotDragRecognizer: GestureRecognizerFactoryWithHandlers<_SlotDragRecognizer>(
                          () => _SlotDragRecognizer(
                            dragThreshold: param.dragThreshold,
                            dragMode: _DragMode.resizeTop,
                            onStart: _onDragStart,
                            onUpdate: _onDragUpdate,
                            onEnd: _resetDrag,
                            onTap: () {},
                          ),
                          (instance) {},
                        ),
                      };
                      return RawGestureDetector(behavior: HitTestBehavior.opaque, gestures: gestures);
                    },
                  ),
                ),

              // ── Layer 2: bottom resize handle (immediate drag) ───
              if (hasResize)
                Positioned(
                  bottom: 0, left: 0, right: 0, height: zoneSize,
                  child: Builder(
                    builder: (ctx) {
                      final gestures = <Type, GestureRecognizerFactory>{
                        _SlotDragRecognizer: GestureRecognizerFactoryWithHandlers<_SlotDragRecognizer>(
                          () => _SlotDragRecognizer(
                            dragThreshold: param.dragThreshold,
                            dragMode: _DragMode.resizeBottom,
                            onStart: _onDragStart,
                            onUpdate: _onDragUpdate,
                            onEnd: _resetDrag,
                            onTap: () {},
                          ),
                          (instance) {},
                        ),
                      };
                      return RawGestureDetector(behavior: HitTestBehavior.opaque, gestures: gestures);
                    },
                  ),
                ),

              // ── Layer 3: handle indicators (visual only) ────────
              if (hasResize && param.showHandles)
                param.topHandleBuilder?.call() ?? _buildHandleIndicator(accent, isTop: true),
              if (hasResize && param.showHandles)
                param.bottomHandleBuilder?.call() ?? _buildHandleIndicator(accent, isTop: false),
            ],
          ),
        ),
      ),
    );
  }

  // ── long-press drag handlers (for shift mode on the slot body) ──────
  // These replace the old immediate-drag _SlotDragRecognizer on the body
  // so that quick flings / swipes over a slot continue to navigate the
  // calendar.  Only a deliberate long-press-then-drag shifts the slot.

  void _onLongPressStart(LongPressStartDetails details) {
    _log('Long press start — initiating shift drag');
    _onDragStart(_DragMode.shift);
    _lastLongPressGlobalPosition = details.globalPosition;
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (_session == null) return;
    final delta = details.globalPosition - _lastLongPressGlobalPosition;
    _lastLongPressGlobalPosition = details.globalPosition;
    _handleDragUpdate(delta, details.globalPosition);
  }

  void _onLongPressEnd() {
    _log('Long press end');
    _resetDrag();
  }

  /// Builds the body of a multi-day slot: per-day segments, pill handles,
  /// and drag-target overlays confined to the resize-handle zones.
  ///
  /// The centre of the slot has NO gesture recognizer — pointer events
  /// pass through to the scroll views behind it.  Only the narrow handle
  /// zones at the absolute start and end of the slot receive their own
  /// drag recognizers.
  List<Widget> _buildMultiDayBody(ThemeData theme, Color accent, double borderRadius) {
    final mapper = widget.timeMapper;
    final param = widget.dayParam.slotInteractionConfig;
    final slot = widget.slot;
    final canDrag = param.enableShift;
    final hasResize = param.enableResize;
    final zoneSize = param.handleZoneSize;
    final handlesVisible = hasResize && param.showHandles;
    // ── Compute positions continuously during drag ──────────────────
    // Using the session snap + accumulated delta instead of widget.slot
    // avoids flicker from parent rebuilds delivering intermediate values.
    // Column count (totalDays) is only overridden for resizeBottom where
    // the end can cross day boundaries; for resizeTop/shift the parent's
    // slot.totalDaysSpanned is authoritative.
    final double dragEndMinute;
    final double dragStartMinuteOfDay;
    final int totalDays;
    if (_session != null) {
      final snapStartMin = _session!.snapStartDate.totalMinutes;
      final snapEndAbs = snapStartMin + _session!.snapDurationMin;
      if (_session!.mode == _DragMode.resizeBottom) {
        dragEndMinute = (snapEndAbs + _accumulatedDelta.dy / mapper.heightPerMinute).toDouble();
        dragStartMinuteOfDay = snapStartMin.toDouble();
        final effectiveEnd = (dragEndMinute > 0 && dragEndMinute % PlannerTimeMapper.minutesPerDay == 0)
            ? dragEndMinute - 1
            : dragEndMinute;
        totalDays = effectiveEnd <= 0 ? 1 : ((effectiveEnd - 1) ~/ PlannerTimeMapper.minutesPerDay).toInt() + 1;
      } else if (_session!.mode == _DragMode.resizeTop) {
        dragEndMinute = snapEndAbs.toDouble();
        final rawStart = (snapStartMin + _accumulatedDelta.dy / mapper.heightPerMinute).toDouble();
        dragStartMinuteOfDay = rawStart.clamp(0.0, PlannerTimeMapper.minutesPerDay.toDouble());
        totalDays = slot.totalDaysSpanned;
      } else {
        // shift: both start and end move together
        final shift = _accumulatedDelta.dy / mapper.heightPerMinute;
        dragEndMinute = (snapEndAbs + shift).toDouble();
        dragStartMinuteOfDay = (snapStartMin + shift).toDouble();
        totalDays = slot.totalDaysSpanned;
      }
    } else {
      dragEndMinute = (slot.startDateTime.totalMinutes + slot.durationInMinutes).toDouble();
      dragStartMinuteOfDay = slot.startDateTime.totalMinutes.toDouble();
      totalDays = slot.totalDaysSpanned;
    }
    // endMinuteOfDay: midnight → 1440 (bottom), not 0 (top).
    final rawEnd = dragEndMinute % PlannerTimeMapper.minutesPerDay;
    final endMinuteOfDay = (rawEnd == 0 && dragEndMinute > 0)
        ? PlannerTimeMapper.minutesPerDay.toDouble()
        : rawEnd;

    if (debugDragPosition) {
      debugPrint('[dragPos] _buildMultiDayBody '
          'mode=${_session?.mode} '
          'dragEndMinute=${dragEndMinute.toStringAsFixed(1)} '
          'totalDays=$totalDays '
          'endMinuteOfDay=${endMinuteOfDay.toStringAsFixed(1)} '
          'startMinuteOfDay=${dragStartMinuteOfDay.toStringAsFixed(1)} '
          'slot.durationInMinutes=${slot.durationInMinutes} '
          'slot.totalDaysSpanned=${slot.totalDaysSpanned} '
          'snapTotalDays=${_session?.snapTotalDays} '
          'accumDy=${_accumulatedDelta.dy.toStringAsFixed(1)}');
    }

    final dayHeight = mapper.totalDayHeight();
    final dayWidth = widget.dayWidth;
    final cellGapPad = widget.cellGapWidthPadding;
    final paddedWidth = dayWidth - cellGapPad * 2;
    final colPositions = widget.columnsParam.getColumPositions(paddedWidth, slot.columnIndex);
    final colWidth = colPositions[1] - colPositions[0];
    final startMinuteOfDay = dragStartMinuteOfDay;

    final startY = mapper.minuteToY(startMinuteOfDay);
    var endY = mapper.minuteToY(endMinuteOfDay);
    // Gap correction: when the last segment ends exactly on an hour
    // boundary, subtract the cell gap so the slot does not cover it
    // (consistent with single-day slot and event rendering).
    if (mapper.cellGapHeight > 0 &&
        endMinuteOfDay > 0 &&
        endMinuteOfDay < PlannerTimeMapper.minutesPerDay &&
        endMinuteOfDay % PlannerTimeMapper.minutesPerHour == 0) {
      endY -= mapper.cellGapHeight;
    }

    final List<Widget> children = [];

    // ── 1. Per-day _SlotBody segments (ignore pointer) ────────────
    // All visual content below is wrapped in IgnorePointer so it does
    // not absorb hit tests.  Only the drag-target overlays (section 3)
    // participate in the gesture arena.  This lets horizontal/vertical
    // scroll pass through the slot's body.
    for (int d = 0; d < totalDays; d++) {
      final isFirst = d == 0;
      final isLast = d == totalDays - 1;
      final isFull = !isFirst && !isLast;

      final double segTop;
      final double segHeight;

      if (isFirst) {
        segTop = startY;
        segHeight = dayHeight - startY;
      } else if (isFull) {
        segTop = 0;
        segHeight = dayHeight;
      } else {
        segTop = 0;
        segHeight = endY;
      }

      final bool hideTop = !isFirst;
      final bool hideBottom = !isLast;

      children.add(
        Positioned(
          left: d * dayWidth,
          top: segTop,
          width: colWidth,
          height: segHeight,
          child: IgnorePointer(
            child: _SlotBody(
              accent: accent,
              borderRadius: borderRadius,
              hideTopBorder: hideTop,
              hideBottomBorder: hideBottom,
              child: _buildMultiDaySegmentContent(
                theme: theme,
                accent: accent,
                slot: slot,
                segmentIndex: d,
                totalDays: totalDays,
                handlesVisible: handlesVisible,
              ),
            ),
          ),
        ),
      );
    }

    // ── 2. Visible pill handles (ignore pointer) ─────────────────
    if (handlesVisible) {
      children.add(
        Positioned(
          left: 6,
          top: startY + 6,
          width: colWidth - 12,
          child: IgnorePointer(
            child: Align(alignment: Alignment.topCenter, child: _buildHandlePill(accent)),
          ),
        ),
      );
      final lastLeft = (totalDays - 1) * dayWidth;
      children.add(
        Positioned(
          left: lastLeft + 6,
          top: endY - 14,
          width: colWidth - 12,
          child: IgnorePointer(
            child: Align(alignment: Alignment.bottomCenter, child: _buildHandlePill(accent)),
          ),
        ),
      );
    }

    // ── 3. Drag-target overlays (ACTIVE hit testing) ─────────────
    // Only these participate in the gesture arena; they are small
    // strips at the centre of each handle zone.
    if (hasResize) {
      final double dragWidth = 40.0;
      final double dragLeft = (colWidth - dragWidth) / 2;

      // Top resize handle — first day, startY..startY+zoneSize.
      children.add(
        Positioned(
          left: dragLeft,
          top: startY,
          width: dragWidth,
          height: zoneSize,
          child: _MultiDayDragTarget(
            dragThreshold: param.dragThreshold,
            dragMode: _DragMode.resizeTop,
            onDragStart: _onDragStart,
            onDragUpdate: _onDragUpdate,
            onDragEnd: _resetDrag,
          ),
        ),
      );

      // Bottom resize handle — last day, endY-zoneSize..endY.
      final lastLeft2 = (totalDays - 1) * dayWidth + dragLeft;
      children.add(
        Positioned(
          left: lastLeft2,
          top: endY - zoneSize,
          width: dragWidth,
          height: zoneSize,
          child: _MultiDayDragTarget(
            dragThreshold: param.dragThreshold,
            dragMode: _DragMode.resizeBottom,
            onDragStart: _onDragStart,
            onDragUpdate: _onDragUpdate,
            onDragEnd: _resetDrag,
          ),
        ),
      );
    }

    // ── 4. Body shift zones (long-press drag for shift) ─────────
    // These cover the body area between the resize handles and use
    // the system long-press gesture so quick flings pass through
    // to the scroll views.  Placed BEFORE the resize drag targets
    // in the stack so handles take priority for hit testing.
    if (canDrag) {
      for (int d = 0; d < totalDays; d++) {
        final isFirst = d == 0;
        final isLast = d == totalDays - 1;

        final double shiftTop;
        final double shiftHeight;

        if (isFirst && isLast) {
          // Single-day multi-day: body between handles.
          shiftTop = startY + (hasResize ? zoneSize : 0);
          final rawShiftBottom = endY - (hasResize ? zoneSize : 0);
          shiftHeight = (rawShiftBottom - shiftTop).clamp(0.0, dayHeight);
        } else if (isFirst) {
          shiftTop = startY + (hasResize ? zoneSize : 0);
          shiftHeight = (dayHeight - shiftTop).clamp(0.0, dayHeight);
        } else if (isLast) {
          shiftTop = 0;
          final rawShiftBottom = endY - (hasResize ? zoneSize : 0);
          shiftHeight = rawShiftBottom.clamp(0.0, dayHeight);
        } else {
          shiftTop = 0;
          shiftHeight = dayHeight;
        }

        if (shiftHeight > 0) {
          children.add(
            Positioned(
              left: d * dayWidth,
              top: shiftTop,
              width: colWidth,
              height: shiftHeight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPressStart: _onLongPressStart,
                onLongPressMoveUpdate: _onLongPressMoveUpdate,
                onLongPressEnd: (_) => _onLongPressEnd(),
              ),
            ),
          );
        }
      }
    }

    return children;
  }

  /// Builds the text content for one segment of a multi-day slot.
  ///
  /// The first segment shows the start time label at its top, the last
  /// segment shows the end time label at its bottom, and any full-day
  /// segments in between show a centered summary label with the overall
  /// date range and times.
  Widget _buildMultiDaySegmentContent({
    required ThemeData theme,
    required Color accent,
    required CalendarSlot slot,
    required int segmentIndex,
    required int totalDays,
    required bool handlesVisible,
  }) {
    final use24Hour = widget.dayParam.slotInteractionConfig.use24HourFormat;

    String formatTime(DateTime dt) {
      final hour = dt.hour;
      final minute = dt.minute.toTimeText();
      if (use24Hour) {
        return '${hour.toTimeText()}:$minute';
      }
      final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
      final period = hour >= 12 ? 'pm' : 'am';
      return '$hour12:$minute $period';
    }

    final start = slot.startDateTime;
    final end = slot.endDateTime;
    final isFirst = segmentIndex == 0;
    final isLast = segmentIndex == totalDays - 1;
    final isFull = !isFirst && !isLast;

    final vPadding = handlesVisible ? _handlePadding : 7.0;

    if (isFirst) {
      // Show start time at top of first segment.
      return Padding(
        padding: EdgeInsets.only(top: vPadding, left: 6, right: 6),
        child: Align(
          alignment: Alignment.topCenter,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              formatTime(start),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: accent, fontSize: 12),
            ),
          ),
        ),
      );
    }

    if (isFull) {
      // Centered summary: "Jan 1 6pm – Jan 2 7am"
      final startLabel = '${start.month}/${start.day} ${formatTime(start)}';
      final endLabel = '${end.month}/${end.day} ${formatTime(end)}';
      return Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              spacing: 6,
              children: [
                Text(
                  startLabel,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500, color: accent, fontSize: 11),
                ),
                Text(
                  endLabel,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500, color: accent, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Last segment: show end time at bottom.
    return Padding(
      padding: EdgeInsets.only(bottom: vPadding, left: 6, right: 6),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            formatTime(end),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: accent, fontSize: 12),
          ),
        ),
      ),
    );
  }

  /// Called by the [Listener] wrapper when a PointerCancelEvent arrives
  /// at the render-object level.  This fires even when the gesture arena
  /// is in an accepted state and would normally not forward the cancel.
  void _onPointerCancelled() {
    _log('Listener.onPointerCancel — forcing drag reset');
    _resetDrag();
  }

  // ── default content ─────────────────────────────────────────────────

  /// Minimum slot pixel height below which default text is hidden
  /// to prevent overflow on compressed slots (e.g., 15-minute events).
  static const double _minTextHeight = 52.0;

  /// Minimum slot pixel height to show the full layout (time range
  /// and duration). Below this only the start time is shown.
  static const double _fullTextHeight = 76.0;

  /// Extra vertical padding to keep text clear of handle indicators.
  static const double _handlePadding = 14.0;

  /// Maximum slot width below which horizontal padding is reduced
  /// to give text more room in narrow columns (e.g., 7-day view).
  static const double _narrowWidthThreshold = 80.0;

  Widget _buildDefaultContent(ThemeData theme, Color accent, double borderRadius) {
    final param = widget.dayParam.slotInteractionConfig;
    final slot = widget.slot;

    // ── compute slot pixel height ──────────────────────────────────────
    final slotHeight = slot.durationInMinutes * widget.heightPerMinute;

    // ── decide whether to show text ────────────────────────────────────
    final showText = param.showDefaultSlotText && slotHeight >= _minTextHeight;

    if (!showText) {
      return _SlotBody(accent: accent, borderRadius: borderRadius);
    }

    final duration = Duration(minutes: slot.durationInMinutes);
    final start = slot.startDateTime;
    final end = start.add(duration);

    final use24Hour = param.use24HourFormat;
    String formatTime(DateTime dt) {
      final hour = dt.hour;
      final minute = dt.minute.toTimeText();
      if (use24Hour) {
        return '${hour.toTimeText()}:$minute';
      }
      final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
      final period = hour >= 12 ? 'pm' : 'am';
      return '$hour12:$minute $period';
    }

    final startText = formatTime(start);
    final endText = formatTime(end);
    final hours = duration.inHours;
    final remainingMins = duration.inMinutes % 60;
    final durationText = (hours >= 1 ? '${hours}h ' : '') + (remainingMins != 0 ? '${remainingMins}m' : '');

    // ── determine layout density ──────────────────────────────────────
    final isCompact = slotHeight < _fullTextHeight;

    // ── extra padding to avoid overlapping handle indicators ───────────
    final handlesVisible = param.enableResize && param.showHandles;

    return _SlotBody(
      accent: accent,
      borderRadius: borderRadius,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < _narrowWidthThreshold;
          final hPadding = isNarrow ? 4.0 : 12.0;
          return Padding(
            padding: EdgeInsets.fromLTRB(hPadding, handlesVisible ? _handlePadding : 7, hPadding, handlesVisible ? _handlePadding : 7),
            child: isCompact ? _buildCompactText(theme, accent, startText, endText) : _buildFullText(theme, accent, startText, endText, durationText),
          );
        },
      ),
    );
  }

  Widget _buildCompactText(ThemeData theme, Color accent, String startText, String endText) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            startText,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: accent, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildFullText(ThemeData theme, Color accent, String startText, String endText, String durationText) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            startText,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: accent, fontSize: 12),
          ),
        ),
        // const Spacer(),
        // FittedBox(
        //   fit: BoxFit.scaleDown,
        //   child: Text(
        //     durationText.trim(),
        //     textAlign: TextAlign.center,
        //     style: theme.textTheme.bodySmall?.copyWith(
        //       fontSize: 10,
        //       color: accent,
        //     ),
        //   ),
        // ),
        const Spacer(),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            endText,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: accent, fontSize: 12),
          ),
        ),
      ],
    );
  }

  // ── handle indicator (small pill) ────────────────────────────────────

  /// Returns just the handle pill [Container] without any [Positioned]
  /// wrapper.  Useful when the caller already provides its own positioning
  /// (e.g., multi-day slot handles placed directly in a Stack).
  Widget _buildHandlePill(Color accent) {
    return Container(
      width: 36,
      height: 4,
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(3)),
    );
  }

  Widget _buildHandleIndicator(Color accent, {required bool isTop}) {
    return Positioned(
      top: isTop ? 6 : null,
      bottom: isTop ? null : 6,
      left: 6,
      right: 6,
      child: Align(alignment: isTop ? Alignment.topCenter : Alignment.bottomCenter, child: _buildHandlePill(accent)),
    );
  }

  // ── cursor on hover ──────────────────────────────────────────────────

  void _onHover(PointerHoverEvent event) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final localPos = renderBox.globalToLocal(event.position);
    final localY = localPos.dy;
    final localX = localPos.dx;
    final height = renderBox.size.height;
    final slot = widget.slot;
    final isMultiDay = slot.totalDaysSpanned > 1;

    if (!widget.dayParam.slotInteractionConfig.enableResize) {
      _updateCursor(SystemMouseCursors.grab);
      return;
    }

    final zoneSize = widget.dayParam.slotInteractionConfig.handleZoneSize;
    final mapper = widget.timeMapper;
    final dayHeight = mapper.totalDayHeight();
    final dayWidth = widget.dayWidth;

    if (isMultiDay) {
      // Multi-day: determine which semantic zone the pointer is in.
      final pointerDay = (localX / dayWidth).floor().clamp(0, slot.totalDaysSpanned - 1);
      final startMinuteOfDay = slot.startDateTime.totalMinutes.toDouble();
      final startY = mapper.minuteToY(startMinuteOfDay);
      final endMinuteOfDay = slot.endMinuteOfDay.toDouble();
      final endY = mapper.minuteToY(endMinuteOfDay);

      // Top handle: pointer is on the first day and near the top of the first segment.
      if (pointerDay == 0 && localY >= startY && localY <= startY + zoneSize) {
        _updateCursor(SystemMouseCursors.resizeUp);
        return;
      }
      // Bottom handle: pointer is on the last day and near the bottom of the last segment.
      if (pointerDay == slot.totalDaysSpanned - 1 && localY >= endY - zoneSize && localY <= endY) {
        _updateCursor(SystemMouseCursors.resizeDown);
        return;
      }
      _updateCursor(SystemMouseCursors.grab);
      return;
    }

    // Single-day: pick the nearest handle when zones overlap.
    final distToTop = localY;
    final distToBottom = height - localY;
    if (distToTop <= zoneSize && distToTop <= distToBottom) {
      _updateCursor(SystemMouseCursors.resizeUp);
    } else if (distToBottom <= zoneSize) {
      _updateCursor(SystemMouseCursors.resizeDown);
    } else {
      _updateCursor(SystemMouseCursors.grab);
    }
  }

  void _updateCursor(MouseCursor? cursor) {
    if (cursor != null && _effectiveCursor != cursor) {
      setState(() => _effectiveCursor = cursor);
    }
  }

  // ── immediate-drag handlers (no long-press delay) ────────────────────

  void _onDragStart(_DragMode? preSetMode) {
    if (debugAutoScroll) {
      debugPrint('[autoScroll] _onDragStart called (preSetMode=$preSetMode)');
    }

    widget.onDragStart?.call();

    // For multi-day handles _MultiDayDragTarget threads the mode through
    // the recognizer.  For single-day slots, preSetMode is null and we
    // detect from pointer position on the first update.
    _preSetMode = preSetMode;
    _accumulatedDelta = Offset.zero;

    // Kill any running ballistic scroll activity (a leftover fling) so
    // it doesn't fight our auto-scroll jumpTo calls.  jumpTo calls
    // goIdle() internally, which disposes any active activity including
    // ballistic, and puts the position in IdleScrollActivity.
    final hc = widget.horizontalScrollController;
    if (hc?.hasClients == true) {
      hc!.jumpTo(hc.offset);
    }
    final vc = widget.verticalScrollController;
    if (vc?.hasClients == true) {
      vc!.jumpTo(vc.offset);
    }

    _stopAutoScroll();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _handleDragUpdate(details.delta, details.globalPosition);
  }

  /// Shared drag-update logic usable from both the immediate-drag
  /// recognizer (resize handles) and the long-press handler (shift).
  void _handleDragUpdate(Offset delta, Offset globalPosition) {
    // Accumulate raw pixel delta — this is independent of widget position,
    // so it stays correct even as the slot is repositioned mid-drag.
    _accumulatedDelta += delta;
    _lastGlobalPosition = globalPosition;
    _lastDragUpdateTime = DateTime.now();

    if (_session == null) {
      // ── First update: determine mode and create the session ──────
      final mode = _preSetMode ?? _DragMode.shift;

      // ── Clear _preSetMode immediately so it can never leak into a
      // subsequent drag session (e.g. when the gesture recognizer
      // lifecycle delivers events out of the expected order).
      _preSetMode = null;

      if (debugAutoScroll) {
        debugPrint('[autoScroll] drag mode set to $mode');
      }

      // Snapshot the slot state (immutable for the drag lifetime).
      final slot = widget.slot;
      _session = _SlotDragSession(
        mode: mode,
        snapStartDate: slot.startDateTime,
        snapEndDate: slot.startDateTime.add(Duration(minutes: slot.durationInMinutes)),
        snapDurationMin: slot.durationInMinutes,
        snapTotalDays: slot.totalDaysSpanned,
      );

      setState(() {
        _isDragging = true;
        _effectiveCursor = mode == _DragMode.shift ? SystemMouseCursors.grabbing : SystemMouseCursors.resizeUpDown;
      });

      widget.dayParam.slotInteractionConfig.onLongPress?.call(slot);
    }

    if (debugAutoScroll) {
      debugPrint(
        '[autoScroll] _handleDragUpdate called, delta=(${delta.dx.toStringAsFixed(1)},${delta.dy.toStringAsFixed(1)}) '
        'mode=${_session!.mode}',
      );
    }

    _applyDrag(_accumulatedDelta);
    _updateAutoScroll();
  }

  void _resetDrag() {
    _log('_resetDrag called (session=${_session != null}, mode=${_session?.mode}, dragging=$_isDragging, timer=${_autoScrollTimer != null})');
    _stopAutoScroll();
    // Ensure scroll controllers are in a clean idle state so that
    // normal scroll physics (fling, snap-to-boundary) resume correctly.
    final hc = widget.horizontalScrollController;
    if (hc?.hasClients == true) {
      hc!.jumpTo(hc.offset);
    }
    final vc = widget.verticalScrollController;
    if (vc?.hasClients == true) {
      vc!.jumpTo(vc.offset);
    }
    // Guard against double-call: addAllowedPointer may call onEnd again
    // if a new pointer arrives before the old recognizer is disposed.
    if (_session != null) {
      final wasResize = _session!.mode != _DragMode.shift;
      widget.onDragEnd?.call(isResize: wasResize);
    }
    _session = null;
    _preSetMode = null;
    _accumulatedDelta = Offset.zero;
    _lastGlobalPosition = Offset.zero;
    // Only call setState if we're still mounted and actually dragging.
    if (mounted && _isDragging) {
      setState(() => _isDragging = false);
    }
    _updateCursor(SystemMouseCursors.basic);
  }

  // ── auto-scroll (edge-triggered) ────────────────────────────────────

  /// Set to `true` to print auto-scroll diagnostics to the console.
  static bool debugAutoScroll = false;

  /// Set to `true` to log drag positioning details (end minute, columns, Y).
  static bool debugDragPosition = true;

  /// Inspects the last-known global pointer position and starts, updates,
  /// or stops edge-triggered auto-scrolling.
  void _updateAutoScroll() {
    if (widget.autoScrollThreshold <= 0) {
      if (debugAutoScroll) debugPrint('[autoScroll] SKIP: threshold <= 0');
      return;
    }
    final hasVertical = widget.verticalScrollController?.hasClients == true;
    final hasHorizontal = widget.horizontalScrollController?.hasClients == true;
    if (!hasVertical && !hasHorizontal) {
      if (debugAutoScroll) {
        debugPrint(
          '[autoScroll] SKIP: no scroll clients '
          '(v=${widget.verticalScrollController != null}, vClients=${widget.verticalScrollController?.hasClients}, '
          'h=${widget.horizontalScrollController != null}, hClients=${widget.horizontalScrollController?.hasClients})',
        );
      }
      return;
    }

    final viewportBounds = _getViewportBounds();
    if (viewportBounds == null) {
      if (debugAutoScroll) debugPrint('[autoScroll] SKIP: viewportBounds is null');
      return;
    }

    final pos = _lastGlobalPosition;
    final threshold = widget.autoScrollThreshold;
    final maxSpeed = widget.autoScrollMaxSpeed;

    double verticalSpeed = 0;
    double horizontalSpeed = 0;

    // Vertical edge proximity.
    if (hasVertical) {
      final topDist = pos.dy - viewportBounds.top;
      final bottomDist = viewportBounds.bottom - pos.dy;
      if (debugAutoScroll) {
        debugPrint(
          '[autoScroll] vp=(top:${viewportBounds.top.toStringAsFixed(0)}, '
          'btm:${viewportBounds.bottom.toStringAsFixed(0)}, '
          'h:${viewportBounds.height.toStringAsFixed(0)}) '
          'ptr=(${pos.dx.toStringAsFixed(0)},${pos.dy.toStringAsFixed(0)}) '
          'topDist=${topDist.toStringAsFixed(0)} '
          'btmDist=${bottomDist.toStringAsFixed(0)} '
          'thresh=$threshold',
        );
      }
      if (topDist < threshold) {
        verticalSpeed = -_computeScrollSpeed(topDist, threshold, maxSpeed);
      } else if (bottomDist < threshold) {
        verticalSpeed = _computeScrollSpeed(bottomDist, threshold, maxSpeed);
      }
    }

    // Horizontal edge proximity.
    if (hasHorizontal) {
      final leftDist = pos.dx - viewportBounds.left;
      final rightDist = viewportBounds.right - pos.dx;
      if (leftDist < threshold) {
        horizontalSpeed = -_computeScrollSpeed(leftDist, threshold, maxSpeed);
      } else if (rightDist < threshold) {
        horizontalSpeed = _computeScrollSpeed(rightDist, threshold, maxSpeed);
      }
    }

    if (verticalSpeed == 0 && horizontalSpeed == 0) {
      _stopAutoScroll();
      return;
    }

    if (debugAutoScroll) {
      debugPrint(
        '[autoScroll] START timer vSpeed=${verticalSpeed.toStringAsFixed(1)} '
        'hSpeed=${horizontalSpeed.toStringAsFixed(1)}',
      );
    }

    // Start or continue the auto-scroll timer.
    if (_autoScrollTimer == null || !_autoScrollTimer!.isActive) {
      _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 16), _onAutoScrollTick);
    }
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  /// Called every ~16ms while the pointer is near a viewport edge.
  void _onAutoScrollTick(Timer timer) {
    if (!mounted || !_isDragging) {
      timer.cancel();
      _autoScrollTimer = null;
      return;
    }

    // If no drag-update has arrived recently the pointer was likely
    // stolen by the system (e.g., Android edge gesture) without a
    // cancel / reject event.  Stop scrolling to prevent the timer
    // from interfering with subsequent normal scroll gestures.
    if (DateTime.now().difference(_lastDragUpdateTime) > _autoScrollStaleTimeout) {
      if (debugAutoScroll) {
        debugPrint('[autoScroll] STOP timer — stale (no drag update ' + 'for >${_autoScrollStaleTimeout.inMilliseconds}ms)');
      }
      timer.cancel();
      _autoScrollTimer = null;
      // Don't corrupt drag state here — the gesture recognizer
      // lifecycle handles reset via onEnd/rejectGesture/cancel.
      // Only stop scrolling; the drag session stays intact.
      return;
    }

    final viewportBounds = _getViewportBounds();
    if (viewportBounds == null) {
      return;
    }

    final pos = _lastGlobalPosition;
    final threshold = widget.autoScrollThreshold;
    final maxSpeed = widget.autoScrollMaxSpeed;

    double verticalScrollAmount = 0;
    double horizontalScrollAmount = 0;

    // Recalculate speeds based on current pointer position.
    if (widget.verticalScrollController?.hasClients == true) {
      final topDist = pos.dy - viewportBounds.top;
      final bottomDist = viewportBounds.bottom - pos.dy;
      if (topDist < threshold) {
        verticalScrollAmount = -_computeScrollSpeed(topDist, threshold, maxSpeed);
      } else if (bottomDist < threshold) {
        verticalScrollAmount = _computeScrollSpeed(bottomDist, threshold, maxSpeed);
      }
    }

    if (widget.horizontalScrollController?.hasClients == true) {
      final leftDist = pos.dx - viewportBounds.left;
      final rightDist = viewportBounds.right - pos.dx;
      if (leftDist < threshold) {
        horizontalScrollAmount = -_computeScrollSpeed(leftDist, threshold, maxSpeed);
      } else if (rightDist < threshold) {
        horizontalScrollAmount = _computeScrollSpeed(rightDist, threshold, maxSpeed);
      }
    }

    if (verticalScrollAmount == 0 && horizontalScrollAmount == 0) {
      if (debugAutoScroll) {
        debugPrint('[autoScroll] STOP timer — no longer near edge');
      }
      _stopAutoScroll();
      return;
    }

    bool scrolled = false;

    // ── vertical scroll ────────────────────────────────────────────
    if (verticalScrollAmount != 0) {
      final controller = widget.verticalScrollController!;
      final oldOffset = controller.offset;
      final newOffset = (oldOffset + verticalScrollAmount).clamp(controller.position.minScrollExtent, controller.position.maxScrollExtent);
      final actualDelta = newOffset - oldOffset;
      if (actualDelta.abs() > 0.01) {
        controller.jumpTo(newOffset);
        // When content scrolls down the slot must move down by the same
        // amount to stay under the pointer.
        _accumulatedDelta += Offset(0, actualDelta);
        scrolled = true;
      }
    }

    // ── horizontal scroll ──────────────────────────────────────────
    // When content scrolls horizontally the slot must move by the same
    // amount to stay under the pointer (the slot's viewport position
    // depends on the scroll offset).  We compensate _accumulatedDelta
    // immediately, mirroring the vertical approach above.
    if (horizontalScrollAmount != 0) {
      final controller = widget.horizontalScrollController!;
      final oldOffset = controller.offset;
      final newOffset = (oldOffset + horizontalScrollAmount).clamp(controller.position.minScrollExtent, controller.position.maxScrollExtent);
      final actualDelta = newOffset - oldOffset;
      if (actualDelta.abs() > 0.01) {
        controller.jumpTo(newOffset);
        // Compensate _accumulatedDelta so the slot stays under the
        // pointer.  Direction: when scroll moves right (+actualDelta)
        // the content shifts left, so the pointer is further right
        // relative to the content; a positive delta moves the slot
        // to a later day, keeping it under the finger.
        _accumulatedDelta += Offset(actualDelta, 0);
        scrolled = true;
      }
    }

    // ── apply accumulated scroll to the slot ───────────────────────
    if (scrolled) {
      _applyDrag(_accumulatedDelta);
    }
  }

  /// Linear speed ramp: 0 at [threshold]-pixels from the edge,
  /// [maxSpeed] at (or past) the edge.
  double _computeScrollSpeed(double distanceFromEdge, double threshold, double maxSpeed) {
    if (distanceFromEdge >= threshold) {
      return 0;
    }
    if (distanceFromEdge <= 0) {
      return maxSpeed;
    }
    return maxSpeed * (1.0 - distanceFromEdge / threshold);
  }

  /// Shared viewport-bounds detection usable from both [InteractiveSlot]
  /// and external callers like [DayWidget].
  ///
  /// Walks up the render tree from [context] to find the planner viewport
  /// [RenderBox] and returns its global bounds, excluding the given insets
  /// (typically the time-indicator column width).
  ///
  /// Falls back to the screen size (minus safe areas) if no suitable
  /// ancestor is found.
  static Rect? viewportBoundsOf(BuildContext context, {double leftInset = 0, double rightInset = 0}) {
    // Start from the parent so the calling widget's own RenderBox is
    // never mistaken for the viewport.  This matters for InteractiveSlot
    // whose own box can grow past the 200 px height threshold during a
    // resize-top drag, causing it to falsely match.
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
          } catch (_) {
            // Transform might be unavailable — keep walking.
          }
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
        final globalOffset = best!.localToGlobal(Offset.zero);
        if (debugAutoScroll) {
          debugPrint(
            '[autoScroll] selected viewport: '
            'type=${best.runtimeType} '
            'size=${best.size.width.toStringAsFixed(0)}x${best.size.height.toStringAsFixed(0)} '
            'global=(${globalOffset.dx.toStringAsFixed(0)},${globalOffset.dy.toStringAsFixed(0)}) '
            'insetL=${leftInset.toStringAsFixed(0)} '
            'insetR=${rightInset.toStringAsFixed(0)}',
          );
        }
        return Rect.fromLTWH(globalOffset.dx + leftInset, globalOffset.dy, best!.size.width - leftInset - rightInset, best!.size.height);
      } catch (_) {}
    }

    // Fallback: use the screen dimensions from MediaQuery.
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

  Rect? _getViewportBounds() {
    return viewportBoundsOf(context, leftInset: widget.viewportLeftInset, rightInset: widget.viewportRightInset);
  }

  // ── drag application ─────────────────────────────────────────────────

  void _applyDrag(Offset localOffset) {
    final mapper = widget.timeMapper;
    final param = widget.dayParam.slotInteractionConfig;
    final round = param.stepMinutesResolver?.call(widget.slot.columnIndex, widget.slot.startDateTime) ?? widget.dayParam.onSlotMinutesRound;
    final alwaysBefore = widget.dayParam.onSlotRoundAlwaysBefore;

    int roundMins(double value, int step) {
      if (alwaysBefore) {
        return step * (value / step).floor();
      }
      return step * (value / step).round();
    }

    switch (_session!.mode) {
      case _DragMode.shift:
        _applyShiftDrag(localOffset, mapper, round, roundMins);
        break;
      case _DragMode.resizeTop:
        _applyResizeTopDrag(localOffset, mapper, round, roundMins);
        break;
      case _DragMode.resizeBottom:
        _applyResizeBottomDrag(localOffset, mapper, round, roundMins);
        break;
    }
  }

  void _applyShiftDrag(
    Offset localOffset,
    PlannerTimeMapper mapper,
    int round,
    int Function(double, int) roundMins,
  ) {
    final slot = widget.slot;
    final rawMinutesDelta = localOffset.dy / mapper.heightPerMinute;
    final daysDelta = (localOffset.dx / widget.dayWidth).round();
    final targetMidnight = _session!.snapStartDate.withoutTime.addCalendarDays(daysDelta);
    // DateTime.add handles minute values that cross day boundaries, so
    // we no longer clamp to a single-day range.  Multi-day slots can
    // freely move across midnight.
    final newStart = targetMidnight.add(
      Duration(
        minutes: roundMins(
          _session!.snapStartDate.totalMinutes + rawMinutesDelta,
          round,
        ),
      ),
    );
    // Only clamp if multi-day is NOT enabled and the slot would cross midnight.
    final maxDuration = widget.dayParam.slotInteractionConfig.maxDurationMinutes;
    if (maxDuration == null) {
      final maxStartMinute = PlannerTimeMapper.minutesPerDay - _session!.snapDurationMin;
      final effectiveMinutes = newStart.difference(targetMidnight).inMinutes;
      final clampedMinute = effectiveMinutes.clamp(0, maxStartMinute);
      if (clampedMinute != effectiveMinutes) {
        final clampedStart = targetMidnight.add(Duration(minutes: clampedMinute));
        final resultSlot = CalendarSlot(
          columnIndex: slot.columnIndex,
          initialStartDate: slot.initialStartDate,
          startDateTime: clampedStart,
          duration: Duration(minutes: _session!.snapDurationMin),
        );
        widget.onChanged(resultSlot);
        return;
      }
    }
    // ── Universal midnight guard ────────────────────────────────────
    // Never let the end cross past midnight when shifting.
    final endMinute = newStart.totalMinutes + _session!.snapDurationMin;
    if (endMinute > PlannerTimeMapper.minutesPerDay) {
      // End would cross past midnight — clamp start so end lands at midnight.
      final safeStartMinute = PlannerTimeMapper.minutesPerDay - _session!.snapDurationMin;
      final safeStart = targetMidnight.add(Duration(minutes: safeStartMinute));
      if (debugDragPosition) {
        debugPrint('[dragPos] shift CLAMPED '
            'endMinute=$endMinute '
            'safeStartMinute=$safeStartMinute '
            'targetMidnight=${targetMidnight.toIso8601String()}');
      }
      final resultSlot = CalendarSlot(
        columnIndex: slot.columnIndex,
        initialStartDate: slot.initialStartDate,
        startDateTime: safeStart,
        duration: Duration(minutes: _session!.snapDurationMin),
      );
      widget.onChanged(resultSlot);
      return;
    }
    if (debugDragPosition) {
      debugPrint('[dragPos] shift OK '
          'endMinute=$endMinute '
          'startMinute=${newStart.totalMinutes} '
          'daysDelta=$daysDelta '
          'snapDurationMin=${_session!.snapDurationMin}');
    }
    final resultSlot = CalendarSlot(
      columnIndex: slot.columnIndex,
      initialStartDate: slot.initialStartDate,
      startDateTime: newStart,
      duration: Duration(minutes: _session!.snapDurationMin),
    );
    widget.onChanged(resultSlot);
  }

  void _applyResizeTopDrag(
    Offset localOffset,
    PlannerTimeMapper mapper,
    int round,
    int Function(double, int) roundMins,
  ) {
    final slot = widget.slot;
    final rawMinutesDelta = localOffset.dy / mapper.heightPerMinute;
    final snapMidnight = _session!.snapStartDate.withoutTime;
    // DateTime.add naturally handles negative minute values (previous day).
    final newStart = snapMidnight.add(
      Duration(
        minutes: roundMins(
          _session!.snapStartDate.totalMinutes + rawMinutesDelta,
          round,
        ),
      ),
    );
    var newDuration = _session!.snapEndDate.difference(newStart).inMinutes;
    final maxDuration = widget.dayParam.slotInteractionConfig.maxDurationMinutes;
    if (maxDuration != null) {
      final maxMinutes = widget.dayParam.slotInteractionConfig
          .maxDurationMinutes;
      // Never clamp below the snap duration — a slot that already
      // exceeds the column-span limit (e.g. created programmatically)
      // should not be forcibly shrunk when the handle is first grabbed.
      final effectiveMax = max(maxMinutes!, _session!.snapDurationMin);
      newDuration = newDuration.clamp(round, effectiveMax);
    } else {
      // Legacy: single-day cap.
      final maxTopMinute = PlannerTimeMapper.minutesPerDay - round;
      final effective = newStart.difference(snapMidnight).inMinutes;
      final clamped = effective.clamp(0, maxTopMinute);
      if (clamped != effective) {
        final clampedStart = snapMidnight.add(Duration(minutes: clamped));
        newDuration = _session!.snapEndDate.difference(clampedStart).inMinutes;
      }
      if (newDuration > PlannerTimeMapper.minutesPerDay) {
        newDuration = PlannerTimeMapper.minutesPerDay;
      }
    }
    // ── Universal midnight guard ────────────────────────────────────
    // Never let the end cross past midnight when resizing the top.
    final endMinute = newStart.totalMinutes + newDuration;
    if (endMinute > PlannerTimeMapper.minutesPerDay) {
      newDuration = PlannerTimeMapper.minutesPerDay - newStart.totalMinutes;
    }
    if (debugDragPosition) {
      debugPrint('[dragPos] resizeTop '
          'endMinute=$endMinute '
          'newStartMinute=${newStart.totalMinutes} '
          'newDuration=$newDuration '
          'snapDurationMin=${_session!.snapDurationMin} '
          'localOffset.dy=${localOffset.dy.toStringAsFixed(1)}');
    }
    // Enforce minimum slot duration.
    final minDuration = widget.dayParam.slotInteractionConfig.minDurationMinutes;
    if (newDuration < minDuration) newDuration = minDuration;

    if (newDuration != slot.durationInMinutes && newDuration >= round) {
      final resultSlot = CalendarSlot(
        columnIndex: slot.columnIndex,
        initialStartDate: slot.initialStartDate,
        startDateTime: newStart,
        duration: Duration(minutes: newDuration),
      );
      widget.onChanged(resultSlot);
    }
  }

  void _applyResizeBottomDrag(
    Offset localOffset,
    PlannerTimeMapper mapper,
    int round,
    int Function(double, int) roundMins,
  ) {
    final slot = widget.slot;
    // Convert pixel delta directly to minutes — a slot's height is always
    // duration × heightPerMinute with no cell gaps inside, so this avoids
    // the fragile minuteToYExtended / yToMinuteExtended round-trip.
    final rawMinutesDelta = localOffset.dy / mapper.heightPerMinute;
    final snapEndMinute =
        _session!.snapStartDate.totalMinutes + _session!.snapDurationMin;
    final snappedEndMinute = roundMins(
      snapEndMinute + rawMinutesDelta,
      round,
    );
    var newDuration =
        snappedEndMinute - _session!.snapStartDate.totalMinutes;
    // Cap duration based on configured maximum duration.
    final maxDuration = widget.dayParam.slotInteractionConfig.maxDurationMinutes;
    if (maxDuration != null) {
      final maxMinutes = widget.dayParam.slotInteractionConfig
          .maxDurationMinutes;
      // Never clamp below the snap duration — a slot that already
      // exceeds the column-span limit (e.g. created programmatically)
      // should not be forcibly shrunk when the handle is first grabbed.
      final effectiveMax = max(maxMinutes!, _session!.snapDurationMin);
      if (newDuration > effectiveMax) newDuration = effectiveMax;
    } else {
      final maxDuration = PlannerTimeMapper.minutesPerDay - _session!.snapStartDate.totalMinutes;
      if (newDuration > maxDuration) {
        newDuration = maxDuration;
      }
    }
    // ── Universal midnight guard ────────────────────────────────────
    // Never let the end cross past the nearest midnight boundary,
    // matching single-day behavior for all slots.  To extend into
    // another day the user must use the API.
    final nextMidnight = ((snapEndMinute - 1) ~/ PlannerTimeMapper.minutesPerDay + 1) * PlannerTimeMapper.minutesPerDay;
    final maxMidnightDuration = nextMidnight - _session!.snapStartDate.totalMinutes;
    if (newDuration > maxMidnightDuration) {
      newDuration = maxMidnightDuration;
    }
    if (debugDragPosition) {
      debugPrint('[dragPos] resizeBottom '
          'snapEndMinute=$snapEndMinute '
          'nextMidnight=$nextMidnight '
          'maxMidnightDuration=$maxMidnightDuration '
          'newDuration=$newDuration '
          'localOffset.dy=${localOffset.dy.toStringAsFixed(1)} '
          'hpm=${mapper.heightPerMinute.toStringAsFixed(2)} '
          'slotDuration=${slot.durationInMinutes}');
    }
    // Enforce minimum slot duration.
    final minDuration = widget.dayParam.slotInteractionConfig.minDurationMinutes;
    if (newDuration < minDuration) newDuration = minDuration;

    if (newDuration != slot.durationInMinutes && newDuration >= round) {
      final resultSlot = CalendarSlot(
        columnIndex: slot.columnIndex,
        initialStartDate: slot.initialStartDate,
        startDateTime: _session!.snapStartDate,
        duration: Duration(minutes: newDuration),
      );
      widget.onChanged(resultSlot);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// _MultiDayDragTarget — a narrow drag zone for a multi-day slot handle.
// ═══════════════════════════════════════════════════════════════════════════

class _MultiDayDragTarget extends StatelessWidget {
  const _MultiDayDragTarget({
    required this.dragThreshold,
    required this.dragMode,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final double dragThreshold;
  final _DragMode dragMode;
  final void Function(_DragMode? mode) onDragStart;
  final void Function(DragUpdateDetails) onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: <Type, GestureRecognizerFactory>{
        _SlotDragRecognizer: GestureRecognizerFactoryWithHandlers<_SlotDragRecognizer>(
          () => _SlotDragRecognizer(
            dragThreshold: dragThreshold,
            dragMode: dragMode,
            onStart: onDragStart,
            onUpdate: onDragUpdate,
            onEnd: onDragEnd,
            onTap: () {},
          ),
          (instance) {},
        ),
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// _SlotBody — filled rounded rectangle used as the default slot body.
// Optionally shows text content via [child].
// ═══════════════════════════════════════════════════════════════════════════

class _SlotBody extends StatelessWidget {
  const _SlotBody({required this.accent, required this.borderRadius, this.child, this.hideTopBorder = false, this.hideBottomBorder = false});

  final Color accent;
  final double borderRadius;
  final Widget? child;
  final bool hideTopBorder;
  final bool hideBottomBorder;

  @override
  Widget build(BuildContext context) {
    final fillColor = accent.withAlpha(30);
    final side = BorderSide(color: accent, width: 2);
    final none = BorderSide.none;
    // Conditionally suppress top / bottom edges for multi-day segments.
    final effectiveBorder = hideTopBorder || hideBottomBorder
        ? Border(left: side, right: side, top: hideTopBorder ? none : side, bottom: hideBottomBorder ? none : side)
        : Border.all(color: accent, width: 2);
    // Keep corners sharp where the adjacent border is hidden so the
    // segment looks continuous with its neighbour.
    final topRadius = hideTopBorder ? Radius.zero : Radius.circular(borderRadius);
    final bottomRadius = hideBottomBorder ? Radius.zero : Radius.circular(borderRadius);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fillColor,
        border: effectiveBorder,
        borderRadius: BorderRadius.vertical(top: topRadius, bottom: bottomRadius),
      ),
      child: child ?? const SizedBox.expand(),
    );
  }
}
