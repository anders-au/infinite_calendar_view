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
    this.verticalScrollController,
    this.horizontalScrollController,
    this.autoScrollThreshold = 40.0,
    this.autoScrollMaxSpeed = 8.0,
    this.viewportLeftInset = 0,
    this.viewportRightInset = 0,
    this.onDragStart,
    this.onDragEnd,
  });

  final TimedSlotSelection slot;
  final double dayWidth;
  final DayParam dayParam;
  final ColumnsParam columnsParam;
  final double heightPerMinute;
  final PlannerTimeMapper? plannerTimeMapper;
  final void Function(TimedSlotSelection? updatedSlot) onChanged;

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
  final VoidCallback? onDragEnd;

  PlannerTimeMapper get timeMapper =>
      plannerTimeMapper ?? PlannerTimeMapper(heightPerMinute: heightPerMinute);

  @override
  State<InteractiveSlot> createState() => InteractiveSlotState();
}

class InteractiveSlotState extends State<InteractiveSlot> {
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

  // ── auto-scroll state ───────────────────────────────────────────────
  Timer? _autoScrollTimer;
  Offset _lastGlobalPosition = Offset.zero;

  @override
  void dispose() {
    _stopAutoScroll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final param = widget.dayParam.slotSelectionParam;
    final accent = param.accentColor ?? theme.colorScheme.secondary;
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

  Widget _buildDefaultContent(
    ThemeData theme,
    Color accent,
    double borderRadius,
  ) {
    final param = widget.dayParam.slotSelectionParam;
    final slot = widget.slot;

    // ── compute slot pixel height ──────────────────────────────────────
    final slotHeight = slot.durationInMinutes * widget.heightPerMinute;

    // ── decide whether to show text ────────────────────────────────────
    final showText = param.showDefaultSlotText &&
        slotHeight >= _minTextHeight;

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
    final durationText = (hours >= 1 ? '${hours}h ' : '') +
        (remainingMins != 0 ? '${remainingMins}m' : '');

    // ── determine layout density ──────────────────────────────────────
    final isCompact = slotHeight < _fullTextHeight;

    // ── extra padding to avoid overlapping handle indicators ───────────
    final handlesVisible = param.enableSlotSelectionResize && param.showHandles;

    return _SlotBody(
      accent: accent,
      borderRadius: borderRadius,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < _narrowWidthThreshold;
          final hPadding = isNarrow ? 4.0 : 12.0;
          return Padding(
            padding: EdgeInsets.fromLTRB(
              hPadding,
              handlesVisible ? _handlePadding : 7,
              hPadding,
              handlesVisible ? _handlePadding : 7,
            ),
            child: isCompact
                ? _buildCompactText(theme, accent, startText, endText)
                : _buildFullText(
                    theme, accent, startText, endText, durationText),
          );
        },
      ),
    );
  }

  Widget _buildCompactText(
    ThemeData theme,
    Color accent,
    String startText,
    String endText,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            startText,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: accent,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFullText(
    ThemeData theme,
    Color accent,
    String startText,
    String endText,
    String durationText,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            startText,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: accent,
              fontSize: 12,
            ),
          ),
        ),
        const Spacer(),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            durationText.trim(),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 10,
              color: accent,
            ),
          ),
        ),
        const Spacer(),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            endText,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: accent,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  // ── handle indicator (small pill) ────────────────────────────────────

  Widget _buildHandleIndicator(Color accent, {required bool isTop}) {
    return Positioned(
      top: isTop ? 6 : null,
      bottom: isTop ? null : 6,
      left: 6,
      right: 6,
      child: Align(
        alignment: isTop ? Alignment.topCenter : Alignment.bottomCenter,
        child: Container(
          width: 36,
          height: 4,
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

    final zoneSize = widget.dayParam.slotSelectionParam.handleZoneSize;

    if (localY < zoneSize) {
      _updateCursor(SystemMouseCursors.resizeUp);
    } else if (localY > height - zoneSize) {
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
    if (debugAutoScroll) {
      debugPrint('[autoScroll] _onDragStart called');
    }
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    widget.onDragStart?.call();

    _dragMode = null;
    _dragCommitted = false;
    _accumulatedDelta = Offset.zero;

    // Kill any running ballistic scroll activity (a leftover fling) so
    // it doesn't fight our auto-scroll jumpTo calls.  We use animateTo
    // with a non-zero duration to go through beginActivity, which
    // disposes the old activity.  The target equals current offset so
    // the driven animation is zero-displacement; when it completes,
    // goBallistic(0) leaves the controller idle.
    final hc = widget.horizontalScrollController;
    if (hc?.hasClients == true) {
      hc!.animateTo(
        hc.offset,
        duration: const Duration(milliseconds: 16),
        curve: Curves.linear,
      );
    }
    final vc = widget.verticalScrollController;
    if (vc?.hasClients == true) {
      vc!.animateTo(
        vc.offset,
        duration: const Duration(milliseconds: 16),
        curve: Curves.linear,
      );
    }

    _stopAutoScroll();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (debugAutoScroll) {
      debugPrint('[autoScroll] _onDragUpdate called, delta=(${details.delta.dx.toStringAsFixed(1)},${details.delta.dy.toStringAsFixed(1)}) '
          'mode=$_dragMode');
    }
    // Accumulate raw pixel delta — this is independent of widget position,
    // so it stays correct even as the slot is repositioned mid-drag.
    _accumulatedDelta += details.delta;
    _lastGlobalPosition = details.globalPosition;

    if (_dragMode == null) {
      // First movement — determine mode from the touch position.
      final renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox == null) return;

      // On the very first PointerMoveEvent the widget hasn't moved yet
      // (no onChanged has fired), so localPosition is accurate.
      final height = renderBox.size.height;
      final param = widget.dayParam.slotSelectionParam;
      final hasResize = param.enableSlotSelectionResize;
      final zoneSize = param.handleZoneSize;
      final localY = renderBox.globalToLocal(details.globalPosition).dy;

      if (hasResize && localY < zoneSize) {
        _dragMode = _DragMode.resizeTop;
      } else if (hasResize && localY > height - zoneSize) {
        _dragMode = _DragMode.resizeBottom;
      } else {
        _dragMode = _DragMode.shift;
      }

      if (debugAutoScroll) {
        debugPrint('[autoScroll] drag mode set to $_dragMode');
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
    _updateAutoScroll();
  }

  void _resetDrag() {
    _stopAutoScroll();
    widget.onDragEnd?.call();
    _dragMode = null;
    _dragCommitted = false;
    _accumulatedDelta = Offset.zero;
    _lastGlobalPosition = Offset.zero;
    setState(() => _isDragging = false);
    _updateCursor(SystemMouseCursors.basic);
  }

  // ── auto-scroll (edge-triggered) ────────────────────────────────────

  /// Set to `true` to print auto-scroll diagnostics to the console.
  static bool debugAutoScroll = false;

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
        debugPrint('[autoScroll] SKIP: no scroll clients '
            '(v=${widget.verticalScrollController != null}, vClients=${widget.verticalScrollController?.hasClients}, '
            'h=${widget.horizontalScrollController != null}, hClients=${widget.horizontalScrollController?.hasClients})');
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
        debugPrint('[autoScroll] vp=(top:${viewportBounds.top.toStringAsFixed(0)}, '
            'btm:${viewportBounds.bottom.toStringAsFixed(0)}, '
            'h:${viewportBounds.height.toStringAsFixed(0)}) '
            'ptr=(${pos.dx.toStringAsFixed(0)},${pos.dy.toStringAsFixed(0)}) '
            'topDist=${topDist.toStringAsFixed(0)} '
            'btmDist=${bottomDist.toStringAsFixed(0)} '
            'thresh=$threshold');
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
      debugPrint('[autoScroll] START timer vSpeed=${verticalSpeed.toStringAsFixed(1)} '
          'hSpeed=${horizontalSpeed.toStringAsFixed(1)}');
    }

    // Start or continue the auto-scroll timer.
    if (_autoScrollTimer == null || !_autoScrollTimer!.isActive) {
      _autoScrollTimer = Timer.periodic(
        const Duration(milliseconds: 16),
        _onAutoScrollTick,
      );
    }
  }

  void _stopAutoScroll() {

    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  /// Called every ~16ms while the pointer is near a viewport edge.
  void _onAutoScrollTick(Timer timer) {
    if (!mounted) {
      timer.cancel();
      _autoScrollTimer = null;
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
        verticalScrollAmount =
            -_computeScrollSpeed(topDist, threshold, maxSpeed);
      } else if (bottomDist < threshold) {
        verticalScrollAmount =
            _computeScrollSpeed(bottomDist, threshold, maxSpeed);
      }
    }

    if (widget.horizontalScrollController?.hasClients == true) {
      final leftDist = pos.dx - viewportBounds.left;
      final rightDist = viewportBounds.right - pos.dx;
      if (leftDist < threshold) {
        horizontalScrollAmount =
            -_computeScrollSpeed(leftDist, threshold, maxSpeed);
      } else if (rightDist < threshold) {
        horizontalScrollAmount =
            _computeScrollSpeed(rightDist, threshold, maxSpeed);
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
      final newOffset = (oldOffset + verticalScrollAmount).clamp(
        controller.position.minScrollExtent,
        controller.position.maxScrollExtent,
      );
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
      final newOffset = (oldOffset + horizontalScrollAmount).clamp(
        controller.position.minScrollExtent,
        controller.position.maxScrollExtent,
      );
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
  double _computeScrollSpeed(
    double distanceFromEdge,
    double threshold,
    double maxSpeed,
  ) {
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
  static Rect? viewportBoundsOf(
    BuildContext context, {
    double leftInset = 0,
    double rightInset = 0,
  }) {
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
      screenHeight = MediaQuery.of(context).size.height;
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
          debugPrint('[autoScroll] selected viewport: '
              'type=${best.runtimeType} '
              'size=${best.size.width.toStringAsFixed(0)}x${best.size.height.toStringAsFixed(0)} '
              'global=(${globalOffset.dx.toStringAsFixed(0)},${globalOffset.dy.toStringAsFixed(0)}) '
              'insetL=${leftInset.toStringAsFixed(0)} '
              'insetR=${rightInset.toStringAsFixed(0)}');
        }
        return Rect.fromLTWH(
          globalOffset.dx + leftInset,
          globalOffset.dy,
          best!.size.width - leftInset - rightInset,
          best!.size.height,
        );
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
    return viewportBoundsOf(
      context,
      leftInset: widget.viewportLeftInset,
      rightInset: widget.viewportRightInset,
    );
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
    final targetMidnight =
        _snapStartDate.withoutTime.addCalendarDays(daysDelta);
    var newStart =
        targetMidnight.add(Duration(minutes: _snapStartDate.totalMinutes + minutesDeltaRounded));
    // Clamp to day boundaries: 00:00 – (24:00 – duration).
    final maxStartMinute = PlannerTimeMapper.minutesPerDay - _snapDurationMin;
    final effectiveMinutes = newStart.difference(targetMidnight).inMinutes;
    final clampedMinute = effectiveMinutes.clamp(0, maxStartMinute);
    if (clampedMinute != effectiveMinutes) {
      newStart = targetMidnight.add(Duration(minutes: clampedMinute));
    }
    widget.onChanged(TimedSlotSelection(
      columnIndex: slot.columnIndex,
      initialStartDate: slot.initialStartDate,
      startDateTime: newStart,
      durationInMinutes: _snapDurationMin,
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
    final snapMidnight = _snapStartDate.withoutTime;
    var newStart =
        snapMidnight.add(Duration(minutes: _snapStartDate.totalMinutes + minutesDeltaRounded));
    // Clamp start to 00:00, keep at least one rounding-step from midnight.
    final maxTopMinute = PlannerTimeMapper.minutesPerDay - round;
    final effectiveMinutes = newStart.difference(snapMidnight).inMinutes;
    final clampedMinute = effectiveMinutes.clamp(0, maxTopMinute);
    if (clampedMinute != effectiveMinutes) {
      newStart = snapMidnight.add(Duration(minutes: clampedMinute));
    }
    var newDuration = _snapEndDate.difference(newStart).inMinutes;
    if (newDuration > PlannerTimeMapper.minutesPerDay) {
      newDuration = PlannerTimeMapper.minutesPerDay;
    }
    if (newDuration != slot.durationInMinutes && newDuration >= round) {
      widget.onChanged(TimedSlotSelection(
        columnIndex: slot.columnIndex,
        initialStartDate: slot.initialStartDate,
        startDateTime: newStart,
        durationInMinutes: newDuration,
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
    // Compute the snap-end minute directly from start + duration rather
    // than _snapEndDate.totalMinutes.  When the slot ends at 24:00
    // _snapEndDate is midnight of the *next* day and totalMinutes
    // returns 0, which would map the handle to the very top of the
    // planner and break all drag arithmetic.
    final snapEndMinute = (_snapStartDate.totalMinutes + _snapDurationMin)
        .clamp(0, PlannerTimeMapper.minutesPerDay)
        .toDouble();
    final endY = mapper.minuteToY(snapEndMinute);
    final currentMinute = minuteFromY(endY + localOffset.dy);
    final rawDelta = currentMinute - snapEndMinute;
    final minutesDeltaRounded = roundMins(rawDelta, round);
    var newDuration = _snapDurationMin + minutesDeltaRounded;
    // Clamp end to 24:00 (midnight).
    final maxDuration =
        PlannerTimeMapper.minutesPerDay - _snapStartDate.totalMinutes;
    if (newDuration > maxDuration) newDuration = maxDuration;
    if (newDuration != slot.durationInMinutes && newDuration >= round) {
      widget.onChanged(TimedSlotSelection(
        columnIndex: slot.columnIndex,
        initialStartDate: slot.initialStartDate,
        startDateTime: _snapStartDate,
        durationInMinutes: newDuration,
      ));
    }
  }
}


// ═══════════════════════════════════════════════════════════════════════════
// _SlotBody — filled rounded rectangle used as the default slot body.
// Optionally shows text content via [child].
// ═══════════════════════════════════════════════════════════════════════════

class _SlotBody extends StatelessWidget {
  const _SlotBody({
    required this.accent,
    required this.borderRadius,
    this.child,
  });

  final Color accent;
  final double borderRadius;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final fillColor = accent.withAlpha(30);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fillColor,
        border: Border.all(color: accent, width: 2),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: child ?? const SizedBox.expand(),
    );
  }
}