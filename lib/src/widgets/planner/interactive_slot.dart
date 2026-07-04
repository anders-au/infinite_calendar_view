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
  _SlotDragRecognizer({
    required this.dragThreshold,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onTap,
  });

  final double dragThreshold;
  final VoidCallback onStart;
  final void Function(DragUpdateDetails) onUpdate;
  final VoidCallback onEnd;
  final VoidCallback onTap;

  Offset? _startGlobal;
  bool _dragStarted = false;
  int? _pointer;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (_pointer != null) return;
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
        onStart();
      }
      onUpdate(DragUpdateDetails(
        sourceTimeStamp: event.timeStamp,
        delta: event.localDelta,
        globalPosition: event.position,
        localPosition: event.localPosition,
      ));
    } else if (event is PointerUpEvent) {
      if (!_dragStarted) {
        onTap();
        resolve(GestureDisposition.accepted);
      } else {
        onEnd();
      }
      _finish(event.pointer);
    } else if (event is PointerCancelEvent) {
      _finish(event.pointer);
    }
  }

  @override
  void acceptGesture(int pointer) {}

  @override
  void rejectGesture(int pointer) {
    if (_pointer == pointer) _finish(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

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

enum _DragMode {
  shift,
  resizeTop,
  resizeBottom,
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
  });

  final SlotSelection slot;
  final double dayWidth;
  final DayParam dayParam;
  final ColumnsParam columnsParam;
  final double heightPerMinute;
  final PlannerTimeMapper? plannerTimeMapper;
  final void Function(SlotSelection? updatedSlot) onChanged;

  PlannerTimeMapper get timeMapper =>
      plannerTimeMapper ?? PlannerTimeMapper(heightPerMinute: heightPerMinute);

  @override
  State<InteractiveSlot> createState() => _InteractiveSlotState();
}

class _InteractiveSlotState extends State<InteractiveSlot> {
  // ── drag state ──────────────────────────────────────────────────────
  _DragMode? _dragMode;
  bool _dragCommitted = false;

  // ── snapshots taken at drag start ───────────────────────────────────
  DateTime _snapStartDate = DateTime.now();
  DateTime _snapEndDate = DateTime.now();
  int _snapDurationMin = 0;
  Offset _accumulatedDelta = Offset.zero;

  // ── cursor state ────────────────────────────────────────────────────
  MouseCursor _effectiveCursor = SystemMouseCursors.basic;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final param = widget.dayParam.slotSelectionParam;
    final accent = param.accentColor ?? theme.colorScheme.primary;
    final borderRadius = param.slotBorderRadius;
    final canDrag = param.canDragSlotSelectionAfterShow;

    return MouseRegion(
      cursor: _effectiveCursor,
      onHover: _isDragging ? null : _onHover,
      onExit: _isDragging ? null : (_) => _updateCursor(null),
      child: Builder(
        builder: (innerContext) {
          final gestures = canDrag
              ? <Type, GestureRecognizerFactory>{
                  _SlotDragRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                          _SlotDragRecognizer>(
                    () => _SlotDragRecognizer(
                      dragThreshold: param.dragThreshold,
                      onStart: _onDragStart,
                      onUpdate: _onDragUpdate,
                      onEnd: _resetDrag,
                      onTap: () {
                        param.onSlotSelectionTap?.call(widget.slot);
                        widget.onChanged(null);
                      },
                    ),
                    (instance) {},
                  ),
                }
              : <Type, GestureRecognizerFactory>{};
          return RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: gestures,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(borderRadius),
                boxShadow: _dragCommitted
                    ? [
                        BoxShadow(
                          color: accent.withAlpha(70),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: accent.withAlpha(25),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // ── content ──────────────────────────────────────────
                  Positioned.fill(
                    child: param.slotSelectionContentBuilder
                            ?.call(widget.slot) ??
                        _buildDefaultContent(theme, accent, borderRadius),
                  ),

                  // ── top handle indicator ─────────────────────────────
                  if (param.enableSlotSelectionResize && param.showHandles)
                    param.slotSelectionTopHandleBuilder?.call() ??
                        _buildHandleIndicator(accent, isTop: true),

                  // ── bottom handle indicator ──────────────────────────
                  if (param.enableSlotSelectionResize && param.showHandles)
                    param.slotSelectionBottomHandleBuilder?.call() ??
                        _buildHandleIndicator(accent, isTop: false),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── default Google-Calendar-style content ────────────────────────────

  Widget _buildDefaultContent(
    ThemeData theme,
    Color accent,
    double borderRadius,
  ) {
    final slot = widget.slot;
    final duration = Duration(minutes: slot.durationInMinutes);
    final start = slot.startDateTime;
    final end = start.add(duration);

    final startText =
        '${start.hour.toTimeText()}:${start.minute.toTimeText()}';
    final endText = '${end.hour.toTimeText()}:${end.minute.toTimeText()}';
    final hours = duration.inHours;
    final remainingMins = duration.inMinutes % 60;
    final durationText = (hours >= 1 ? '${hours}h ' : '') +
        (remainingMins != 0 ? '${remainingMins}m' : '');

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: accent.withAlpha(25),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border(
          left: BorderSide(
            color: accent,
            width: 4,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.slot.startDateTime.hour > 11 ? endText : startText,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: accent,
                fontSize: 12,
              ),
            ),
            const Spacer(),
            Text(
              '$startText - $endText',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withAlpha(160),
              ),
            ),
            Text(
              durationText.trim(),
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 10,
                color: theme.colorScheme.onSurface.withAlpha(120),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── handle indicator (small pill) ────────────────────────────────────

  Widget _buildHandleIndicator(Color accent, {required bool isTop}) {
    return Positioned(
      top: isTop ? 0 : null,
      bottom: isTop ? null : 0,
      left: 0,
      right: 0,
      child: Align(
        alignment: isTop ? Alignment.topCenter : Alignment.bottomCenter,
        child: Container(
          width: 36,
          height: 5,
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }

  // ── cursor on hover ──────────────────────────────────────────────────

  void _onHover(PointerHoverEvent event) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final localY = renderBox.globalToLocal(event.position).dy;
    final height = renderBox.size.height;

    if (!widget.dayParam.slotSelectionParam.enableSlotSelectionResize) {
      _updateCursor(SystemMouseCursors.grab);
      return;
    }

    final zoneFraction = widget.dayParam.slotSelectionParam.handleZoneFraction;
    final zoneHeight = height * zoneFraction;

    if (localY < zoneHeight) {
      _updateCursor(SystemMouseCursors.resizeUp);
    } else if (localY > height - zoneHeight) {
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

  void _onDragStart() {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    _dragMode = null;
    _dragCommitted = false;
    _accumulatedDelta = Offset.zero;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    // Accumulate raw pixel delta — this is independent of widget position,
    // so it stays correct even as the slot is repositioned mid-drag.
    _accumulatedDelta += details.delta;

    if (_dragMode == null) {
      // First movement — determine mode from the touch position.
      final renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox == null) return;

      // On the very first PointerMoveEvent the widget hasn't moved yet
      // (no onChanged has fired), so localPosition is accurate.
      final height = renderBox.size.height;
      final param = widget.dayParam.slotSelectionParam;
      final hasResize = param.enableSlotSelectionResize;
      final zoneHeight = height * param.handleZoneFraction;
      final localY = renderBox.globalToLocal(details.globalPosition).dy;

      if (hasResize && localY < zoneHeight) {
        _dragMode = _DragMode.resizeTop;
      } else if (hasResize && localY > height - zoneHeight) {
        _dragMode = _DragMode.resizeBottom;
      } else {
        _dragMode = _DragMode.shift;
      }

      // Snapshot current slot state.
      final slot = widget.slot;
      _snapStartDate = slot.startDateTime;
      _snapEndDate =
          _snapStartDate.add(Duration(minutes: slot.durationInMinutes));
      _snapDurationMin = slot.durationInMinutes;

      setState(() {
        _isDragging = true;
        _effectiveCursor = _dragMode == _DragMode.shift
            ? SystemMouseCursors.grabbing
            : SystemMouseCursors.resizeUpDown;
      });

      param.onSlotSelectionLongPress?.call(slot);
      _dragCommitted = true;
    }

    _applyDrag(_accumulatedDelta);
  }

  void _resetDrag() {
    _dragMode = null;
    _dragCommitted = false;
    _accumulatedDelta = Offset.zero;
    setState(() => _isDragging = false);
    _updateCursor(SystemMouseCursors.basic);
  }

  // ── drag application ─────────────────────────────────────────────────

  void _applyDrag(Offset localOffset) {
    final mapper = widget.timeMapper;
    final round = widget.dayParam.onSlotMinutesRound;
    final alwaysBefore = widget.dayParam.onSlotRoundAlwaysBefore;

    int roundMins(double value, int step) {
      if (alwaysBefore) {
        return step * (value / step).floor();
      }
      return step * (value / step).round();
    }

    double minuteFromY(double y) => mapper.yToMinute(y);

    switch (_dragMode) {
      case _DragMode.shift:
        _applyShiftDrag(localOffset, mapper, round, roundMins, minuteFromY);
        break;
      case _DragMode.resizeTop:
        _applyResizeTopDrag(localOffset, mapper, round, roundMins, minuteFromY);
        break;
      case _DragMode.resizeBottom:
        _applyResizeBottomDrag(
            localOffset, mapper, round, roundMins, minuteFromY);
        break;
      case null:
        break;
    }
  }

  void _applyShiftDrag(
    Offset localOffset,
    PlannerTimeMapper mapper,
    int round,
    int Function(double, int) roundMins,
    double Function(double) minuteFromY,
  ) {
    final slot = widget.slot;
    final initialMinute = _snapStartDate.totalMinutes.toDouble();
    final initialY = mapper.minuteToY(initialMinute);
    final currentMinute = minuteFromY(initialY + localOffset.dy);
    final minutesDelta = currentMinute - initialMinute;
    final minutesDeltaRounded = roundMins(minutesDelta, round);
    final daysDelta = (localOffset.dx / widget.dayWidth).round();
    final newStart = _snapStartDate
        .addCalendarDays(daysDelta)
        .add(Duration(minutes: minutesDeltaRounded));
    widget.onChanged(SlotSelection(
      slot.columnIndex,
      slot.initialStartDateTime,
      newStart,
      _snapDurationMin,
    ));
  }

  void _applyResizeTopDrag(
    Offset localOffset,
    PlannerTimeMapper mapper,
    int round,
    int Function(double, int) roundMins,
    double Function(double) minuteFromY,
  ) {
    final slot = widget.slot;
    final startMinute = _snapStartDate.totalMinutes.toDouble();
    final startY = mapper.minuteToY(startMinute);
    final currentMinute = minuteFromY(startY + localOffset.dy);
    final rawDelta = currentMinute - startMinute;
    final minutesDeltaRounded = roundMins(rawDelta, round);
    final newStart =
        _snapStartDate.add(Duration(minutes: minutesDeltaRounded));
    final newDuration = _snapEndDate.totalMinutes - newStart.totalMinutes;
    if (newDuration != slot.durationInMinutes && newDuration >= round) {
      widget.onChanged(SlotSelection(
        slot.columnIndex,
        slot.initialStartDateTime,
        newStart,
        newDuration,
      ));
    }
  }

  void _applyResizeBottomDrag(
    Offset localOffset,
    PlannerTimeMapper mapper,
    int round,
    int Function(double, int) roundMins,
    double Function(double) minuteFromY,
  ) {
    final slot = widget.slot;
    final endMinute = _snapEndDate.totalMinutes.toDouble();
    final endY = mapper.minuteToY(endMinute);
    final currentMinute = minuteFromY(endY + localOffset.dy);
    final rawDelta = currentMinute - endMinute;
    final minutesDeltaRounded = roundMins(rawDelta, round);
    final newDuration = _snapDurationMin + minutesDeltaRounded;
    if (newDuration != slot.durationInMinutes && newDuration >= round) {
      widget.onChanged(SlotSelection(
        slot.columnIndex,
        slot.initialStartDateTime,
        _snapStartDate,
        newDuration,
      ));
    }
  }
}
