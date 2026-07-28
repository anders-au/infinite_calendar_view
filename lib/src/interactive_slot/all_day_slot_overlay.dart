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
    this.viewportKey,
    this.autoScrollThreshold = 40.0,
    this.autoScrollMaxSpeed = 8.0,
    this.onChanged,
    this.onDragStart,
    this.onDragEnd,
    this.rowNotifier,
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

  /// Key for the all-day viewport [Stack]. Used to calculate auto-scroll
  /// edge bounds from the exact clipped all-day area.
  final GlobalKey? viewportKey;

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

  /// The all-day row assigned by the event overlay.
  final ValueNotifier<int?>? rowNotifier;

  @override
  State<AllDaySlotOverlay> createState() => _AllDaySlotOverlayState();
}

class _AllDaySlotOverlayState extends State<AllDaySlotOverlay> {
  static const double _edgeVisibilityTolerance = 1.0;
  static bool debugAllDayDrag = false;

  DragSession? _session;
  SlotAutoScroller? _autoScroller;
  _AllDaySlotLayout? _lastInteractiveLayout;
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
    // The lane is allocated by the event overlay. Do not paint a temporary
    // row-zero slot before that allocator has reported a result.
    if (widget.rowNotifier?.value == null) return const SizedBox.shrink();

    var layout = _computeLayout(slot);
    if (layout.rect.isEmpty) {
      if (_session == null || _lastInteractiveLayout == null) {
        _log('build empty layout; no active fallback, returning shrink');
        return const SizedBox.shrink();
      }
      _log('build empty layout during drag; using last interactive layout');
      layout = _lastInteractiveLayout!;
    } else {
      _lastInteractiveLayout = layout;
    }

    final isDragging = _session != null;
    final accent =
        widget.config.accentColor ?? Theme.of(context).colorScheme.secondary;

    return Positioned.fill(
      child: Stack(
        clipBehavior: Clip.none,
        children: _buildStableHandleStack(
          slot,
          accent,
          layout,
          isDragging: isDragging,
        ),
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
    final effectiveViewportWidth =
        widget.viewportWidth ?? _stackWidthFromContext(context);

    // Completely off-screen? Return empty.
    if (naturalLeft + naturalWidth <= 0 ||
        (effectiveViewportWidth != null &&
            naturalLeft >= effectiveViewportWidth)) {
      return _AllDaySlotLayout.zero;
    }

    // Start is off-screen when the natural left edge is before the
    // viewport (sticky-left will clamp to 0).
    final isStartOffScreen =
        naturalLeft < -_edgeVisibilityTolerance &&
        naturalLeft + naturalWidth > 0;

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
    if (effectiveViewportWidth != null) {
      isEndOffScreen =
          naturalLeft + naturalWidth >
          effectiveViewportWidth + _edgeVisibilityTolerance;
    } else {
      // Last-resort fallback: detect via width truncation from
      // sticky-left clamping only.
      isEndOffScreen = width < naturalWidth;
    }

    const rowPadding = 2.0;
    final row = widget.rowNotifier?.value ?? 0;
    final top = rowPadding + row * (widget.eventHeight + rowPadding);

    return _AllDaySlotLayout(
      rect: Rect.fromLTRB(left, top, left + width, top + widget.eventHeight),
      isStartOffScreen: isStartOffScreen,
      isEndOffScreen: isEndOffScreen,
    );
  }

  // ── handle stack ─────────────────────────────────────────────────────

  List<Widget> _buildStableHandleStack(
    CalendarSlot slot,
    Color accent,
    _AllDaySlotLayout layout, {
    required bool isDragging,
  }) {
    final zoneSize = widget.config.handleZoneSize;
    final activeMode = _session?.mode;
    final canResizeStart =
        widget.config.enableResize && widget.config.enableResizeStart;
    final canResizeEnd =
        widget.config.enableResize && widget.config.enableResizeEnd;

    final showLeftHandle = canResizeStart && !layout.isStartOffScreen;
    final showRightHandle = canResizeEnd && !layout.isEndOffScreen;
    final mountLeftHandleZone =
        showLeftHandle || activeMode == DragMode.extendStart;
    final mountRightHandleZone =
        showRightHandle || activeMode == DragMode.extendEnd;

    final rect = layout.rect;
    final shiftLeftInset = showLeftHandle ? zoneSize : 0.0;
    final shiftRightInset = showRightHandle ? zoneSize : 0.0;
    final shiftWidth = (rect.width - shiftLeftInset - shiftRightInset).clamp(
      0.0,
      rect.width,
    );

    _log(
      'build stack active=$activeMode rect=${_formatRect(rect)} '
      'startOff=${layout.isStartOffScreen} endOff=${layout.isEndOffScreen} '
      'showL=$showLeftHandle showR=$showRightHandle '
      'mountL=$mountLeftHandleZone mountR=$mountRightHandleZone '
      'shiftWidth=${shiftWidth.toStringAsFixed(1)}',
    );

    return [
      Positioned.fromRect(
        rect: rect,
        child: IgnorePointer(
          child: SlotRenderer(
            slot: slot,
            config: widget.config,
            accentColor: accent,
            isDragging: _session != null,
            hideLeftBorder: layout.isStartOffScreen,
            hideRightBorder: layout.isEndOffScreen,
            hideLeftHandle: !mountLeftHandleZone,
            hideRightHandle: !mountRightHandleZone,
          ),
        ),
      ),
      Positioned.fromRect(
        rect: rect,
        child: MouseRegion(
          cursor: _effectiveCursor,
          onHover: isDragging ? null : _onHover,
          onExit: isDragging ? null : (_) => _updateCursor(null),
          child: const SizedBox.expand(),
        ),
      ),
      if (widget.config.enableShift && shiftWidth > 0)
        Positioned(
          key: const ValueKey('allDaySlot.shift.positioned'),
          left: rect.left + shiftLeftInset,
          top: rect.top,
          width: shiftWidth,
          height: rect.height,
          child: SlotHandleZone(
            dragMode: DragMode.shift,
            config: widget.config,
            onDragStart: (mode) => _onDragStart(mode),
            onDragUpdate: _onDragUpdate,
            onDragEnd: _onDragEnd,
            onTap: () => widget.config.onTap?.call(slot),
          ),
        ),
      if (mountLeftHandleZone)
        Positioned(
          key: const ValueKey('allDaySlot.extendStart.positioned'),
          left: rect.left,
          top: rect.top,
          width: zoneSize,
          height: rect.height,
          child: SlotHandleZone(
            dragMode: DragMode.extendStart,
            config: widget.config,
            onDragStart: (mode) => _onDragStart(DragMode.extendStart),
            onDragUpdate: _onDragUpdate,
            onDragEnd: _onDragEnd,
          ),
        ),
      if (mountRightHandleZone)
        Positioned(
          key: const ValueKey('allDaySlot.extendEnd.positioned'),
          left: rect.right - zoneSize,
          top: rect.top,
          width: zoneSize,
          height: rect.height,
          child: SlotHandleZone(
            dragMode: DragMode.extendEnd,
            config: widget.config,
            onDragStart: (mode) => _onDragStart(DragMode.extendEnd),
            onDragUpdate: _onDragUpdate,
            onDragEnd: _onDragEnd,
          ),
        ),
      if (showLeftHandle && widget.config.showHandles)
        Positioned(
          left: rect.left + 6,
          top: rect.top + 6,
          height: rect.height - 12,
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
          left: rect.right - 10,
          top: rect.top + 6,
          height: rect.height - 12,
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
    ];
  }

  // ignore: unused_element
  Widget _buildHandleStack(
    CalendarSlot slot,
    Color accent,
    _AllDaySlotLayout layout,
  ) {
    final zoneSize = widget.config.handleZoneSize;
    final activeMode = _session?.mode;
    final visualLayout = layout;
    final canResizeStart =
        widget.config.enableResize && widget.config.enableResizeStart;
    final canResizeEnd =
        widget.config.enableResize && widget.config.enableResizeEnd;

    // Hide handles when their edge is off-screen — the event is "ongoing"
    // and should not show resize affordances on the clipped side. Keep the
    // active handle mounted, though, so auto-scroll drags receive their
    // normal pointer end/cancel lifecycle.
    final showLeftHandle = canResizeStart && !layout.isStartOffScreen;
    final showRightHandle = canResizeEnd && !layout.isEndOffScreen;
    final mountLeftHandleZone =
        showLeftHandle || activeMode == DragMode.extendStart;
    final mountRightHandleZone =
        showRightHandle || activeMode == DragMode.extendEnd;

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
              hideLeftBorder: visualLayout.isStartOffScreen,
              hideRightBorder: visualLayout.isEndOffScreen,
              hideLeftHandle: !mountLeftHandleZone,
              hideRightHandle: !mountRightHandleZone,
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
              key: const ValueKey('allDaySlot.shift'),
              dragMode: DragMode.shift,
              config: widget.config,
              onDragStart: (mode) => _onDragStart(mode),
              onDragUpdate: _onDragUpdate,
              onDragEnd: _onDragEnd,
              onTap: () => widget.config.onTap?.call(slot),
            ),
          ),

        // ── left handle (extend start) ─────────────────────────
        if (mountLeftHandleZone)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: zoneSize,
            child: SlotHandleZone(
              key: const ValueKey('allDaySlot.extendStart'),
              dragMode: DragMode.extendStart,
              config: widget.config,
              onDragStart: (mode) => _onDragStart(DragMode.extendStart),
              onDragUpdate: _onDragUpdate,
              onDragEnd: _onDragEnd,
            ),
          ),

        // ── right handle (extend end) ──────────────────────────
        if (mountRightHandleZone)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: zoneSize,
            child: SlotHandleZone(
              key: const ValueKey('allDaySlot.extendEnd'),
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
    final localX = event.localPosition.dx;
    final width = _lastInteractiveLayout?.rect.width ?? 0;

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

    _log(
      'drag start mode=$mode slot=${_formatSlot(slot)} '
      'mainHasClients=${widget.mainContentScrollController?.hasClients} '
      'headerHasClients=${widget.headerScrollController?.hasClients}',
    );

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
      debugLabel: 'all-day $mode',
      onScroll: (scrollDelta) {
        if (_session == null) return;
        _log(
          'auto-scroll onScroll delta=('
          '${scrollDelta.dx.toStringAsFixed(2)},'
          '${scrollDelta.dy.toStringAsFixed(2)})',
        );
        final afterScroll = _session!.applyUpdate(scrollDelta);
        if (afterScroll != null) {
          _log('auto-scroll emitted ${_formatSlot(afterScroll)}');
          widget.onChanged?.call(afterScroll);
        } else {
          _log('auto-scroll produced no slot update');
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
    if (_session == null) {
      _log('drag update ignored: no session');
      return;
    }

    _log(
      'drag update mode=${_session!.mode} delta=('
      '${details.delta.dx.toStringAsFixed(2)},'
      '${details.delta.dy.toStringAsFixed(2)}) global=('
      '${details.globalPosition.dx.toStringAsFixed(1)},'
      '${details.globalPosition.dy.toStringAsFixed(1)})',
    );

    final updated = _session!.applyUpdate(details.delta);
    if (updated != null) {
      _log('drag update emitted ${_formatSlot(updated)}');
      widget.onChanged?.call(updated);
    } else {
      _log('drag update produced no slot update');
    }

    // Feed auto-scroller with latest position and bounds.
    final bounds = _viewportBounds();
    if (bounds != null) {
      _log('auto-scroll update bounds=${_formatRect(bounds)}');
      _autoScroller?.update(details.globalPosition, bounds);
    } else {
      _log('auto-scroll update skipped: viewport bounds null');
    }
  }

  void _onDragEnd() {
    final mode = _session?.mode;
    if (mode == null) {
      _log('drag end ignored: no active session');
      return;
    }
    _log(
      'drag end mode=$mode slot=${_slot == null ? 'null' : _formatSlot(_slot!)}',
    );
    _session = null;
    _lastInteractiveLayout = null;
    _autoScroller?.dispose();
    _autoScroller = null;
    _updateCursor(SystemMouseCursors.basic);
    widget.onDragEnd?.call(mode);
    widget.config.onDragEnd?.call(mode);
  }

  Rect? _viewportBounds() {
    final fromKey = _allDayViewportBoundsFromKey();
    if (fromKey != null) {
      _log('viewport bounds from key ${_formatRect(fromKey)}');
      return fromKey;
    }
    final fromWidth = _allDayViewportBounds(context);
    if (fromWidth != null) {
      _log('viewport bounds from width ${_formatRect(fromWidth)}');
      return fromWidth;
    }
    final fallback = _findViewportBounds(
      context,
      leftInset: widget.viewportLeftInset,
    );
    _log(
      fallback == null
          ? 'viewport bounds unavailable'
          : 'viewport bounds fallback ${_formatRect(fallback)}',
    );
    return fallback;
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

  Rect? _allDayViewportBounds(BuildContext context) {
    final expectedWidth = widget.viewportWidth;
    if (expectedWidth == null) return null;

    RenderObject? current = context.findRenderObject();
    while (current != null) {
      final parent = current.parent;
      if (parent is RenderObject) {
        current = parent;
      } else {
        break;
      }

      if (current is RenderBox && current.hasSize) {
        final size = current.size;
        if ((size.width - expectedWidth).abs() <= 1.0) {
          final globalOffset = current.localToGlobal(Offset.zero);
          return Rect.fromLTWH(
            globalOffset.dx,
            globalOffset.dy,
            size.width,
            size.height,
          );
        }
      }
    }

    return null;
  }

  Rect? _allDayViewportBoundsFromKey() {
    final renderObject = widget.viewportKey?.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }

    final globalOffset = renderObject.localToGlobal(Offset.zero);
    return Rect.fromLTWH(
      globalOffset.dx,
      globalOffset.dy,
      renderObject.size.width,
      renderObject.size.height,
    );
  }

  void _log(String message) {
    if (!debugAllDayDrag) return;
    debugPrint('[allDaySlot] $message');
  }

  static String _formatRect(Rect rect) {
    return '(${rect.left.toStringAsFixed(1)},'
        '${rect.top.toStringAsFixed(1)},'
        '${rect.right.toStringAsFixed(1)},'
        '${rect.bottom.toStringAsFixed(1)})';
  }

  static String _formatSlot(CalendarSlot slot) {
    return '${slot.startDateTime.toIso8601String()} -> '
        '${slot.endDateTime.toIso8601String()} '
        'days=${slot.totalDaysSpanned}';
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
