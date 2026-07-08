import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../infinite_calendar_view.dart';
import '../../interactive_slot/all_day_slot_overlay.dart';
import '../../interactive_slot/slot_config.dart';
import '../../interactive_slot/slot_selection.dart';
import '../../utils/extension.dart';
import '../../utils/list/infinite_list.dart';
import '../../utils/list/models/alignments.dart';

class HorizontalFullDayEventsWidget extends StatefulWidget {
  const HorizontalFullDayEventsWidget({
    super.key,
    required this.controller,
    this.textDirection = TextDirection.ltr,
    required this.fullDayParam,
    required this.columnsParam,
    required this.cellGapWidthPadding,
    required this.dayHorizontalController,
    required this.maxPreviousDays,
    required this.maxNextDays,
    required this.initialDate,
    required this.dayWidth,
    required this.todayColor,
    required this.timesIndicatorsWidth,
    this.mainContentHorizontalController,
    this.onSlotDragStart,
    this.onSlotDragEnd,
    this.calendarSlotNotifier,
  });

  final EventsController controller;
  final TextDirection textDirection;
  final FullDayParam fullDayParam;
  final ColumnsParam columnsParam;
  final double cellGapWidthPadding;
  final ScrollController dayHorizontalController;
  final int? maxPreviousDays;
  final int? maxNextDays;
  final DateTime initialDate;
  final double dayWidth;
  final Color? todayColor;
  final double timesIndicatorsWidth;

  /// The main planner content horizontal scroll controller.
  /// Auto-scroll drives this controller so the header and content stay
  /// in sync. The header controller syncs automatically via
  /// [EventsPlanner]'s listener.
  final ScrollController? mainContentHorizontalController;

  /// Called when the all-day slot pill starts being dragged.
  final VoidCallback? onSlotDragStart;

  /// Called when the all-day slot pill drag ends.
  final VoidCallback? onSlotDragEnd;

  /// When non-null, uses the new [AllDaySlotOverlay] system instead of the
  /// legacy [AllDayInteractiveSlot].  Set to [EventsPlannerState]'s
  /// `_calendarSlotNotifier` when [EventsPlanner.useNewSlotSystem] is true.
  final ValueNotifier<CalendarSlot?>? calendarSlotNotifier;

  DateTime getDayFromIndex(int index) {
    return initialDate.addCalendarDays(textDirection == TextDirection.ltr ? index : -index);
  }

  @override
  State<HorizontalFullDayEventsWidget> createState() => _HorizontalFullDayEventsWidgetState();
}

class _HorizontalFullDayEventsWidgetState extends State<HorizontalFullDayEventsWidget> {
  /// Tracks the maximum number of event rows needed by the overlay.
  /// Updated every frame by [MultiDayEventsOverlay].
  final ValueNotifier<int> _maxEventRows = ValueNotifier(0);
  late VoidCallback _maxRowsListener;

  @override
  void initState() {
    super.initState();
    _maxRowsListener = () {
      // Defer setState to avoid calling it during the build phase
      // when the overlay updates the notifier inside LayoutBuilder.
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      }
    };
    _maxEventRows.addListener(_maxRowsListener);
  }

  @override
  void dispose() {
    _maxEventRows.removeListener(_maxRowsListener);
    _maxEventRows.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fullDayParam = widget.fullDayParam;
    final columnsParam = widget.columnsParam;
    final controller = widget.controller;
    final textDirection = widget.textDirection;
    final timesIndicatorsWidth = widget.timesIndicatorsWidth;
    final dayWidth = widget.dayWidth;
    final cellGapWidthPadding = widget.cellGapWidthPadding;
    final maxPreviousDays = widget.maxPreviousDays;
    final maxNextDays = widget.maxNextDays;
    final dayHorizontalController = widget.dayHorizontalController;

    // Compute dynamic bar height from the row count reported by the
    // overlay.  The overlay updates _maxEventRows every frame, and the
    // listener above triggers a rebuild so the bar grows/shrinks.
    final barHeight = _computeBarHeight(fullDayParam);

    return Container(
      decoration: fullDayParam.fullDayEventsBarDecoration,
      child: Row(
        textDirection: textDirection,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: timesIndicatorsWidth,
            height: barHeight,
            child:
                fullDayParam.fullDayEventsBarLeftWidget ??
                Center(
                  child: Text(
                    fullDayParam.fullDayEventsBarLeftText,
                    style: TextStyle(color: theme.colorScheme.outline, fontSize: 12),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
          ),
          Expanded(
            child: SizedBox(
              height: barHeight,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  // Per-day backgrounds and single-day full-day events
                  InfiniteList(
                    controller: dayHorizontalController,
                    physics: const NeverScrollableScrollPhysics(),
                    scrollDirection: Axis.horizontal,
                    direction: InfiniteListDirection.multi,
                    negChildCount: maxPreviousDays,
                    posChildCount: maxNextDays,
                    builder: (context, index) {
                      var day = widget.getDayFromIndex(index);
                      var isToday = DateUtils.isSameDay(day, DateTime.now());
                      return InfiniteListItem(
                        contentBuilder: (context) {
                          return SizedBox(
                            width: dayWidth,
                            child: FullDayEventsWidget(
                              controller: controller,
                              isToday: isToday,
                              day: day,
                              todayColor: widget.todayColor,
                              fullDayParam: fullDayParam,
                              columnsParam: columnsParam,
                              dayWidth: dayWidth,
                              cellGapWidthPadding: cellGapWidthPadding,
                            ),
                          );
                        },
                      );
                    },
                  ),
                  // Full-day events overlay — rendered outside the per-day
                  // InfiniteList so multi-day events span day boundaries.
                  // Positioned.fill gives the child fixed constraints from
                  // the Stack size, so LayoutBuilder inside is safe.
                  if (fullDayParam.fullDayEventsBuilder == null)
                    Positioned.fill(
                      child: MultiDayEventsOverlay(
                        controller: controller,
                        scrollController: dayHorizontalController,
                        fullDayParam: fullDayParam,
                        dayWidth: dayWidth,
                        cellGapWidthPadding: cellGapWidthPadding,
                        getDayFromIndex: widget.getDayFromIndex,
                        maxRowsNotifier: _maxEventRows,
                      ),
                    ),
                  // All-day slot selection overlay — a pill that appears
                  // when the user taps or long-presses a day cell in the
                  // all-day bar.  Styled to match InteractiveSlot.
                  _buildAllDaySlotOverlay(controller, columnsParam, fullDayParam, theme, widget.onSlotDragStart, widget.onSlotDragEnd),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Dynamic bar height
  // ═══════════════════════════════════════════════════════════════════════

  double _computeBarHeight(FullDayParam fullDayParam) {
    final rows = _maxEventRows.value;
    if (rows == 0) return fullDayParam.fullDayEventsBarHeight;
    // Each row: eventHeight + 2px padding.
    final rowHeight = fullDayParam.fullDayEventHeight + 2.0;
    return rows * rowHeight + 2.0; // top/bottom padding
  }

  // ═══════════════════════════════════════════════════════════════════════
  // All-day slot selection overlay
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildAllDaySlotOverlay(
    EventsController controller,
    ColumnsParam columnsParam,
    FullDayParam fullDayParam,
    ThemeData theme,
    VoidCallback? onSlotDragStart,
    VoidCallback? onSlotDragEnd,
  ) {
    final param = fullDayParam.allDaySlotSelectionParam;

    // ── New all-day slot system ─────────────────────────────────────
    if (widget.calendarSlotNotifier != null) {
      return _buildNewAllDaySlotOverlay(
        param, columnsParam, fullDayParam, onSlotDragStart, onSlotDragEnd);
    }

    // ── Legacy all-day slot system ──────────────────────────────────
    return AnimatedBuilder(
      animation: Listenable.merge([controller.slotSelectionNotifier, widget.dayHorizontalController]),
      builder: (context, _) {
        final selection = controller.slotSelectionNotifier.value;
        if (selection is! AllDaySlotSelection) return const SizedBox.shrink();

        final dayWidth = widget.dayWidth;
        final pad = widget.cellGapWidthPadding;
        final eventEndGap = fullDayParam.eventEndGap;
        final eventHeight = fullDayParam.fullDayEventHeight;
        const rowPadding = 2.0;

        if (!widget.dayHorizontalController.hasClients) {
          return const SizedBox.shrink();
        }
        final scrollOffset = widget.dayHorizontalController.positions.first.pixels;

        // Compute the start day index from initialDate.
        final startDiff = selection.startDate.withoutTime.difference(widget.initialDate.withoutTime).inDays;
        final startIndex = widget.textDirection == TextDirection.rtl ? -startDiff : startDiff;
        final daysSpan = selection.dayCount;

        // Column offset within the day cell.
        final innerWidth = dayWidth - pad * 2;
        final columnPositions = columnsParam.getColumPositions(innerWidth, selection.columnIndex);

        // Natural left edge (before clamping).
        final naturalLeft = startIndex * dayWidth - scrollOffset + pad + columnPositions[0];
        // Width spans across all days in the selection.
        final naturalWidth = (daysSpan - 1) * dayWidth + columnPositions[1] - columnPositions[0] - eventEndGap;

        // Apply sticky-left for multi-day selections, matching the
        // MultiDayEventsOverlay behaviour.
        final double left;
        final double width;
        if (naturalLeft < 0 && naturalLeft + naturalWidth > 0) {
          // Pill extends past the left edge — clamp the left edge
          // and adjust width to keep the right edge in place.
          left = 0.0;
          width = (naturalLeft + naturalWidth).clamp(1.0, naturalWidth);
        } else {
          left = naturalLeft;
          width = naturalWidth;
        }

        // Visibility culling.
        final viewportWidth = MediaQuery.of(context).size.width - widget.timesIndicatorsWidth;
        if (naturalLeft + naturalWidth <= 0 || naturalLeft >= viewportWidth) {
          return const SizedBox.shrink();
        }

        // Determine whether the actual start/end edges are in the
        // viewport.  Handles are hidden when the corresponding edge
        // is scrolled out of view.
        final edgeThreshold = dayWidth * 0.5;
        final startInView = naturalLeft > -edgeThreshold;
        final endInView = naturalLeft + naturalWidth < viewportWidth + edgeThreshold;

        final double top = rowPadding + selection.rowIndex * (eventHeight + rowPadding);

        return Positioned(
          left: left,
          top: top,
          width: width,
          height: eventHeight,
          child:
              param.slotSelectionContentBuilder?.call(selection) ??
              AllDayInteractiveSlot(
                slot: selection,
                renderLeftHandle: startInView && param.enableResize,
                renderRightHandle: endInView && param.enableResize,
                dayWidth: dayWidth,
                param: param,
                horizontalScrollController: widget.dayHorizontalController,
                mainContentHorizontalController: widget.mainContentHorizontalController,
                viewportLeftInset: widget.timesIndicatorsWidth,
                onDragStart: onSlotDragStart,
                onDragEnd: onSlotDragEnd,
                onChanged: (AllDaySlotSelection? updatedSlot) {
                  controller.slotSelectionNotifier.value = updatedSlot;
                  param.onSlotSelectionChange?.call(updatedSlot);
                },
              ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // New all-day slot overlay (CalendarSlot system)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildNewAllDaySlotOverlay(
    AllDaySlotSelectionParam param,
    ColumnsParam columnsParam,
    FullDayParam fullDayParam,
    VoidCallback? onSlotDragStart,
    VoidCallback? onSlotDragEnd,
  ) {
    final notifier = widget.calendarSlotNotifier!;

    return AnimatedBuilder(
      animation: Listenable.merge([notifier, widget.dayHorizontalController]),
      builder: (context, _) {
        final slot = notifier.value;
        if (slot == null || !slot.isAllDay) return const SizedBox.shrink();

        final innerWidth = widget.dayWidth - widget.cellGapWidthPadding * 2;
        final columnPositions = columnsParam.getColumPositions(
          innerWidth,
          slot.columnIndex,
        );

        final config = SlotInteractionConfig(
          stepMinutes: 15,
          enableShift: param.enableDrag,
          enableExtendStart: param.enableResize,
          enableExtendEnd: param.enableResize,
          enableHorizontalAxis: true,
          enableVerticalAxis: false,
          minDurationMinutes: 1, // 1 day minimum
          showHandles: true,
          handleZoneSize: 40.0, // wider handles for all-day horizontal layout
          dragThreshold: param.dragThreshold,
          accentColor: param.accentColor,
          slotBorderRadius: param.slotBorderRadius,
          showDefaultSlotText: param.showDefaultSlotText,
          onChanged: (updated) {
            notifier.value = updated;
            param.onSlotSelectionChange?.call(
              updated != null
                  ? AllDaySlotSelection(
                      columnIndex: updated.columnIndex,
                      initialStartDate: updated.initialStartDate,
                      startDate: updated.startDateTime,
                      endDate: updated.endDateTime
                          .subtract(const Duration(days: 1)),
                    )
                  : null,
            );
          },
          onTap: (s) => param.onSlotSelectionTap?.call(
            AllDaySlotSelection(
              columnIndex: s.columnIndex,
              initialStartDate: s.initialStartDate,
              startDate: s.startDateTime,
              endDate: s.endDateTime.subtract(const Duration(days: 1)),
            ),
          ),
        );

        return AllDaySlotOverlay(
          slotNotifier: notifier,
          config: config,
          dayWidth: widget.dayWidth,
          eventHeight: fullDayParam.fullDayEventHeight,
          cellGapWidthPadding: widget.cellGapWidthPadding,
          eventEndGap: fullDayParam.eventEndGap,
          columnPositions: columnPositions,
          initialDate: widget.initialDate,
          headerScrollController: widget.dayHorizontalController,
          mainContentScrollController: widget.mainContentHorizontalController,
          viewportLeftInset: widget.timesIndicatorsWidth,
          onDragStart: onSlotDragStart,
          onDragEnd: onSlotDragEnd,
          onChanged: (updated) {
            notifier.value = updated;
            param.onSlotSelectionChange?.call(
              updated != null
                  ? AllDaySlotSelection(
                      columnIndex: updated.columnIndex,
                      initialStartDate: updated.initialStartDate,
                      startDate: updated.startDateTime,
                      endDate: updated.endDateTime
                          .subtract(const Duration(days: 1)),
                    )
                  : null,
            );
          },
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// AllDayInteractiveSlot — a draggable, resizable all-day slot pill that
// mirrors InteractiveSlot but operates on whole-day increments instead of
// minutes.  Rendered inside the all-day bar overlay.
// ═══════════════════════════════════════════════════════════════════════════

enum _AllDayDragMode { shift, resizeLeft, resizeRight }

class _AllDaySlotDragRecognizer extends OneSequenceGestureRecognizer {
  _AllDaySlotDragRecognizer({required this.dragThreshold, required this.onStart, required this.onUpdate, required this.onEnd, required this.onTap});

  final double dragThreshold;
  final void Function(Offset globalPosition) onStart;
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
        onStart(_startGlobal!);
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
  String get debugDescription => '_AllDaySlotDragRecognizer';
}

class AllDayInteractiveSlot extends StatefulWidget {
  const AllDayInteractiveSlot({
    super.key,
    required this.slot,
    this.renderLeftHandle = true,
    this.renderRightHandle = true,
    required this.dayWidth,
    required this.param,
    required this.onChanged,
    this.horizontalScrollController,
    this.mainContentHorizontalController,
    this.autoScrollThreshold = 40.0,
    this.autoScrollMaxSpeed = 8.0,
    this.viewportLeftInset = 0,
    this.viewportRightInset = 0,
    this.onDragStart,
    this.onDragEnd,
  });

  final AllDaySlotSelection slot;

  /// Whether to render the left (resize-start) handle.
  /// Should be false when the selection's start date is scrolled out
  /// of view so the handle doesn't float in empty space.
  final bool renderLeftHandle;

  /// Whether to render the right (resize-end) handle.
  /// Should be false when the selection's end date is scrolled out
  /// of view so the handle doesn't float in empty space.
  final bool renderRightHandle;

  final double dayWidth;
  final AllDaySlotSelectionParam param;
  final void Function(AllDaySlotSelection? updatedSlot) onChanged;

  /// Scroll controller for horizontal edge-triggered auto-scroll.
  /// This is the header/overlay controller; auto-scroll also drives
  /// [mainContentHorizontalController] to keep content in sync.
  final ScrollController? horizontalScrollController;

  /// The main planner content scroll controller. Auto-scroll drives this
  /// controller; the header controller syncs automatically via the
  /// existing listener in [EventsPlanner].
  final ScrollController? mainContentHorizontalController;

  final double autoScrollThreshold;
  final double autoScrollMaxSpeed;
  final double viewportLeftInset;
  final double viewportRightInset;

  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  @override
  State<AllDayInteractiveSlot> createState() => _AllDayInteractiveSlotState();
}

class _AllDayInteractiveSlotState extends State<AllDayInteractiveSlot> {
  _AllDayDragMode? _dragMode;
  bool _dragCommitted = false;
  bool _isDragging = false;

  // Snapshots at drag start.
  DateTime _snapStartDate = DateTime.now();
  DateTime _snapEndDate = DateTime.now();

  // Accumulated horizontal delta for day snapping — never reset;
  // total days offset is computed from this relative to snapshots.
  double _accumulatedDx = 0;

  // Auto-scroll state (viewport-based, mirrors InteractiveSlot).
  Timer? _autoScrollTimer;
  Offset _lastGlobalPosition = Offset.zero;

  // Cursor state.
  MouseCursor _effectiveCursor = SystemMouseCursors.basic;

  @override
  void dispose() {
    _stopAutoScroll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final param = widget.param;
    final accent = param.accentColor ?? theme.colorScheme.secondary;
    final borderRadius = param.slotBorderRadius;
    final canInteract = param.enableDrag || param.enableResize;

    if (!canInteract) {
      // Static pill (original behaviour).
      final fillColor = accent.withAlpha(30);
      return DecoratedBox(
        decoration: BoxDecoration(
          color: fillColor,
          border: Border.all(color: accent, width: 2, strokeAlign: BorderSide.strokeAlignInside),
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: [BoxShadow(color: accent.withAlpha(25), blurRadius: 4, offset: const Offset(0, 1))],
        ),
        child: param.showDefaultSlotText
            ? Center(
                child: Text(
                  _formatDate(widget.slot.startDate),
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: accent, fontSize: 11),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              )
            : const SizedBox.expand(),
      );
    }

    // Interactive pill with drag/resize.
    return MouseRegion(
      cursor: _effectiveCursor,
      onHover: _isDragging ? null : _onHover,
      onExit: _isDragging ? null : (_) => _updateCursor(null),
      child: Builder(
        builder: (innerContext) {
          final gestures = <Type, GestureRecognizerFactory>{
            _AllDaySlotDragRecognizer: GestureRecognizerFactoryWithHandlers<_AllDaySlotDragRecognizer>(
              () => _AllDaySlotDragRecognizer(
                dragThreshold: param.dragThreshold,
                onStart: _onDragStart,
                onUpdate: _onDragUpdate,
                onEnd: _resetDrag,
                onTap: () {
                  param.onSlotSelectionTap?.call(widget.slot);
                },
              ),
              (instance) {},
            ),
          };

          return RawGestureDetector(behavior: HitTestBehavior.opaque, gestures: gestures, child: _buildPill(accent, borderRadius, theme));
        },
      ),
    );
  }

  Widget _buildPill(Color accent, double borderRadius, ThemeData theme) {
    final fillColor = accent.withAlpha(30);
    final param = widget.param;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: _dragCommitted
            ? [BoxShadow(color: accent.withAlpha(70), blurRadius: 10, offset: const Offset(0, 3))]
            : [BoxShadow(color: accent.withAlpha(25), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Fill.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: fillColor,
                border: Border.all(color: accent, width: 2),
                borderRadius: BorderRadius.circular(borderRadius),
              ),
              child: param.showDefaultSlotText ? _buildDateLabels(Theme.of(context), accent) : null,
            ),
          ),
          // Left handle (resize start) — only when the actual start
          // edge is visible in the viewport.
          if (widget.renderLeftHandle) _buildResizeHandle(accent, isLeft: true),
          // Right handle (resize end) — only when the actual end
          // edge is visible in the viewport.
          if (widget.renderRightHandle) _buildResizeHandle(accent, isLeft: false),
        ],
      ),
    );
  }

  /// Builds a resize handle indicator that matches the style of
  /// [InteractiveSlot]'s `_buildHandleIndicator` — a small rounded pill
  /// inset from the edge rather than an edge-to-edge strip.
  Widget _buildResizeHandle(Color accent, {required bool isLeft}) {
    return Positioned(
      left: isLeft ? 6 : null,
      right: isLeft ? null : 6,
      top: 6,
      bottom: 6,
      child: Align(
        alignment: isLeft ? Alignment.centerLeft : Alignment.centerRight,
        child: Container(
          width: 4,
          height: 24,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(3)),
        ),
      ),
    );
  }

  // ── date labels at ends ───────────────────────────────────────────

  Widget _buildDateLabels(ThemeData theme, Color accent) {
    final slot = widget.slot;
    final isSingleDay = DateUtils.isSameDay(slot.startDate, slot.endDate);

    return LayoutBuilder(
      builder: (context, constraints) {

        if (constraints.maxWidth < 60) {
          return const SizedBox.shrink();
        }

        if (isSingleDay) {
          return Center(
            child: Text(
              _formatDate(slot.startDate),
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: accent, fontSize: 11),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }

        // Very narrow pills: just show the start date once, centered.
        if (constraints.maxWidth < 100) {
          return Center(
            child: Text(
              _formatDate(slot.startDate),
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: accent, fontSize: 11),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }
        // Shift text inward when handles are visible so they
        // don't overlap.
        final handlePad = 16.0;
        final edgePad = 6.0;
        final leftPad = widget.renderLeftHandle ? handlePad : edgePad;
        final rightPad = widget.renderRightHandle ? handlePad : edgePad;

        return Stack(
          children: [
            // Start date at left edge.
            Positioned(
              left: leftPad,
              top: 0,
              bottom: 0,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _formatDate(slot.startDate),
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: accent, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            // End date at right edge.
            Positioned(
              right: rightPad,
              top: 0,
              bottom: 0,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  _formatDate(slot.endDate),
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: accent, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── hover cursor ──────────────────────────────────────────────────

  /// Zone in logical pixels from the left/right edge where the cursor
  /// changes to a resize indicator.
  static const double _resizeZoneSize = 20.0;

  void _onHover(PointerHoverEvent event) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final localX = renderBox.globalToLocal(event.position).dx;
    final width = renderBox.size.width;

    if (!widget.param.enableResize) {
      _updateCursor(SystemMouseCursors.grab);
      return;
    }

    if (localX < _resizeZoneSize) {
      _updateCursor(SystemMouseCursors.resizeLeft);
    } else if (localX > width - _resizeZoneSize) {
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

  // ── drag handlers ─────────────────────────────────────────────────

  void _onDragStart(Offset globalPosition) {
    _dragCommitted = true;
    _isDragging = true;
    _snapStartDate = widget.slot.startDate;
    _snapEndDate = widget.slot.endDate;
    _accumulatedDx = 0;
    _lastGlobalPosition = globalPosition;
    _dragMode = _determineDragMode(globalPosition);

    setState(() {
      _effectiveCursor = _dragMode == _AllDayDragMode.shift ? SystemMouseCursors.grabbing : SystemMouseCursors.resizeLeftRight;
    });

    // Cancel any active ballistic scroll on both controllers so
    // jumpTo calls during auto-scroll are not fighting a fling.
    // Use positions.first (not .offset which asserts exactly one client)
    // because the main controller can legitimately be attached to
    // multiple scroll views (e.g. the planner's InfiniteList).
    final mhc = widget.mainContentHorizontalController;
    if (mhc?.hasClients == true) {
      mhc!.animateTo(mhc.positions.first.pixels, duration: const Duration(milliseconds: 16), curve: Curves.linear);
    }
    final hc = widget.horizontalScrollController;
    if (hc?.hasClients == true) {
      hc!.animateTo(hc.positions.first.pixels, duration: const Duration(milliseconds: 16), curve: Curves.linear);
    }

    widget.onDragStart?.call();
  }

  _AllDayDragMode _determineDragMode(Offset globalPosition) {
    if (!widget.param.enableResize) return _AllDayDragMode.shift;

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return _AllDayDragMode.shift;

    final localPos = renderBox.globalToLocal(globalPosition);
    final width = renderBox.size.width;

    if (localPos.dx < _resizeZoneSize) return _AllDayDragMode.resizeLeft;
    if (localPos.dx > width - _resizeZoneSize) {
      return _AllDayDragMode.resizeRight;
    }
    return _AllDayDragMode.shift;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_dragCommitted || _dragMode == null) return;

    _accumulatedDx += details.delta.dx;
    _lastGlobalPosition = details.globalPosition;

    _applyDaySnap();
    _updateAutoScroll();
  }

  void _resetDrag() {
    _dragCommitted = false;
    _isDragging = false;
    _dragMode = null;
    _accumulatedDx = 0;
    _lastGlobalPosition = Offset.zero;
    _stopAutoScroll();
    setState(() => _effectiveCursor = SystemMouseCursors.basic);
    widget.onDragEnd?.call();
  }

  // ── day snapping ──────────────────────────────────────────────────

  /// Computes the total day offset from [_accumulatedDx] relative to
  /// the snapshots and updates the slot model accordingly.
  /// Unlike the old implementation, [_accumulatedDx] is **never reset** —
  /// the total offset is always computed from the original snapshots.
  void _applyDaySnap() {
    if (widget.dayWidth <= 0) return;

    final totalDays = (_accumulatedDx / widget.dayWidth).round();

    switch (_dragMode!) {
      case _AllDayDragMode.shift:
        if (totalDays == 0) return;
        final newStart = _snapStartDate.addCalendarDays(totalDays);
        final newEnd = _snapEndDate.addCalendarDays(totalDays);
        widget.onChanged(widget.slot.copyWith(startDate: newStart, endDate: newEnd));

      case _AllDayDragMode.resizeLeft:
        var newStart = _snapStartDate.addCalendarDays(totalDays);
        if (!newStart.isAfter(_snapEndDate)) {
          widget.onChanged(widget.slot.copyWith(startDate: newStart));
        }

      case _AllDayDragMode.resizeRight:
        var newEnd = _snapEndDate.addCalendarDays(totalDays);
        if (!newEnd.isBefore(_snapStartDate)) {
          widget.onChanged(widget.slot.copyWith(endDate: newEnd));
        }
    }
  }

  // ── auto-scroll (viewport-based, mirrors InteractiveSlot) ─────────

  void _updateAutoScroll() {
    if (widget.autoScrollThreshold <= 0) return;

    final hasMain = widget.mainContentHorizontalController?.hasClients == true;
    final hasHeader = widget.horizontalScrollController?.hasClients == true;
    if (!hasMain && !hasHeader) return;

    final viewportBounds = _getViewportBounds();
    if (viewportBounds == null) return;

    final pos = _lastGlobalPosition;
    final threshold = widget.autoScrollThreshold;
    final maxSpeed = widget.autoScrollMaxSpeed;

    double horizontalSpeed = 0;

    final leftDist = pos.dx - viewportBounds.left;
    final rightDist = viewportBounds.right - pos.dx;
    if (leftDist < threshold) {
      horizontalSpeed = -_computeScrollSpeed(leftDist, threshold, maxSpeed);
    } else if (rightDist < threshold) {
      horizontalSpeed = _computeScrollSpeed(rightDist, threshold, maxSpeed);
    }

    if (horizontalSpeed == 0) {
      _stopAutoScroll();
      return;
    }

    if (_autoScrollTimer == null || !_autoScrollTimer!.isActive) {
      _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 16), _onAutoScrollTick);
    }
  }

  void _onAutoScrollTick(Timer timer) {
    if (!mounted || !_isDragging) {
      _stopAutoScroll();
      return;
    }

    final viewportBounds = _getViewportBounds();
    if (viewportBounds == null) return;

    final pos = _lastGlobalPosition;
    final threshold = widget.autoScrollThreshold;
    final maxSpeed = widget.autoScrollMaxSpeed;

    double horizontalScrollAmount = 0;

    final leftDist = pos.dx - viewportBounds.left;
    final rightDist = viewportBounds.right - pos.dx;
    if (leftDist < threshold) {
      horizontalScrollAmount = -_computeScrollSpeed(leftDist, threshold, maxSpeed);
    } else if (rightDist < threshold) {
      horizontalScrollAmount = _computeScrollSpeed(rightDist, threshold, maxSpeed);
    }

    if (horizontalScrollAmount == 0) {
      _stopAutoScroll();
      return;
    }

    // Drive the main content controller. The header syncs automatically
    // via the existing listener in EventsPlannerState.
    final mainHc = widget.mainContentHorizontalController;
    final headerHc = widget.horizontalScrollController;

    double actualDelta = 0;
    if (mainHc != null && mainHc.hasClients) {
      final oldOffset = mainHc.offset;
      final newOffset = (oldOffset + horizontalScrollAmount).clamp(mainHc.position.minScrollExtent, mainHc.position.maxScrollExtent);
      final delta = newOffset - oldOffset;
      if (delta.abs() > 0.01) {
        mainHc.jumpTo(newOffset);
        actualDelta = delta;
      }
    }

    // Fallback: if no main controller, drive the header directly.
    if (actualDelta == 0 && headerHc != null && headerHc.hasClients) {
      final oldOffset = headerHc.offset;
      final newOffset = (oldOffset + horizontalScrollAmount).clamp(headerHc.position.minScrollExtent, headerHc.position.maxScrollExtent);
      final delta = newOffset - oldOffset;
      if (delta.abs() > 0.01) {
        headerHc.jumpTo(newOffset);
        actualDelta = delta;
      }
    }

    if (actualDelta.abs() > 0.01) {
      // Compensate accumulated delta so the pill tracks the pointer
      // despite the scroll offset change (mirrors InteractiveSlot).
      _accumulatedDx += actualDelta;
      _applyDaySnap();
    }
  }

  double _computeScrollSpeed(double distanceFromEdge, double threshold, double maxSpeed) {
    if (distanceFromEdge >= threshold) return 0;
    if (distanceFromEdge <= 0) return maxSpeed;
    return maxSpeed * (1.0 - distanceFromEdge / threshold);
  }

  Rect? _getViewportBounds() {
    return InteractiveSlotState.viewportBoundsOf(context, leftInset: widget.viewportLeftInset, rightInset: widget.viewportRightInset);
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  // ── formatting ────────────────────────────────────────────────────

  String _formatDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}';
  }
}

/// Overlay that renders ALL full-day events (single-day and multi-day) with
/// a unified greedy row-assignment algorithm so nothing overlaps. Multi-day
/// events span across day boundaries. Must be placed inside a [Positioned.fill]
/// so the [LayoutBuilder] inside receives fixed constraints from the [Stack]
/// size — those never change on scroll, so no layout churn occurs.
class MultiDayEventsOverlay extends StatefulWidget {
  const MultiDayEventsOverlay({
    super.key,
    required this.controller,
    required this.scrollController,
    required this.fullDayParam,
    required this.dayWidth,
    required this.cellGapWidthPadding,
    required this.getDayFromIndex,
    this.maxRowsNotifier,
  });

  final EventsController controller;
  final ScrollController scrollController;
  final FullDayParam fullDayParam;
  final double dayWidth;
  final double cellGapWidthPadding;
  final DateTime Function(int index) getDayFromIndex;

  /// Optional notifier updated each frame with the maximum event row
  /// count (including any slot offset).  Used by the parent widget to
  /// dynamically size the all-day bar.
  final ValueNotifier<int>? maxRowsNotifier;

  @override
  State<MultiDayEventsOverlay> createState() => _MultiDayEventsOverlayState();
}

class _MultiDayEventsOverlayState extends State<MultiDayEventsOverlay> {
  late VoidCallback _scrollListener;
  late VoidCallback _eventsListener;
  late VoidCallback _slotListener;

  @override
  void initState() {
    super.initState();
    _scrollListener = () {
      if (mounted) setState(() {});
    };
    _eventsListener = () {
      if (mounted) setState(() {});
    };
    _slotListener = () {
      if (mounted) setState(() {});
    };
    widget.scrollController.addListener(_scrollListener);
    widget.controller.addListener(_eventsListener);
    widget.controller.slotSelectionNotifier.addListener(_slotListener);
  }

  @override
  void didUpdateWidget(MultiDayEventsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_scrollListener);
      widget.scrollController.addListener(_scrollListener);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_eventsListener);
      oldWidget.controller.slotSelectionNotifier.removeListener(_slotListener);
      widget.controller.addListener(_eventsListener);
      widget.controller.slotSelectionNotifier.addListener(_slotListener);
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_scrollListener);
    widget.controller.removeListener(_eventsListener);
    widget.controller.slotSelectionNotifier.removeListener(_slotListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.scrollController.hasClients) return const SizedBox.shrink();
    // LayoutBuilder is safe here because we are inside Positioned.fill whose
    // constraints come from the fixed-size Stack parent — they never change
    // on scroll, so no layout churn occurs.
    return LayoutBuilder(
      builder: (context, constraints) {
        return _buildOverlay(constraints.maxWidth);
      },
    );
  }

  Widget _buildOverlay(double viewportWidth) {
    if (!widget.scrollController.hasClients) return const SizedBox.shrink();

    final offset = widget.scrollController.positions.first.pixels;
    final pad = widget.cellGapWidthPadding;
    final eventHeight = widget.fullDayParam.fullDayEventHeight;
    const rowPadding = 2.0;
    const lookback = 90;

    final firstVisibleIndex = (offset / widget.dayWidth).floor();
    final lastVisibleIndex = firstVisibleIndex + (viewportWidth / widget.dayWidth).ceil() + 1;

    // Collect all full-day events.
    // Multi-day: only daysIndex==0 (first segment), from lookback window.
    // Single-day: visible range only.
    final Map<UniqueKey, Event> eventByKey = {};
    final Map<UniqueKey, int> startIndexByKey = {};

    for (int i = firstVisibleIndex - lookback; i <= lastVisibleIndex; i++) {
      final day = widget.getDayFromIndex(i);
      final dayEvents = widget.controller.getFilteredDayEvents(
        day,
        returnDayEvents: false,
        returnMultiDayEvents: widget.fullDayParam.showMultiDayEvents,
      );
      for (final e in dayEvents ?? []) {
        if (e.isMultiDay) {
          if ((e.daysIndex ?? 0) != 0) continue;
          if (!eventByKey.containsKey(e.uniqueId)) {
            eventByKey[e.uniqueId] = e;
            startIndexByKey[e.uniqueId] = i;
          }
        } else {
          if (i < firstVisibleIndex || i > lastVisibleIndex) continue;
          eventByKey[e.uniqueId] = e;
          startIndexByKey[e.uniqueId] = i;
        }
      }
    }

    if (eventByKey.isEmpty) {
      final hasSlot = widget.controller.slotSelectionNotifier.value is AllDaySlotSelection;
      widget.maxRowsNotifier?.value = hasSlot ? 1 : 0;
      return const SizedBox.shrink();
    }

    // Compute day spans before sorting so the sort can use span as a
    // tiebreaker (longer / multi-day events first for stable row assignment).
    final Map<UniqueKey, int> spanByKey = {};
    for (final key in eventByKey.keys) {
      final e = eventByKey[key]!;
      int daysSpan = 1;
      if (e.isMultiDay && e.effectiveEndTime != null) {
        final endDay = DateTime(e.effectiveEndTime!.year, e.effectiveEndTime!.month, e.effectiveEndTime!.day);
        final startDay = DateTime(e.startTime.year, e.startTime.month, e.startTime.day);
        daysSpan = endDay.difference(startDay).inDays + 1;
      }
      spanByKey[key] = daysSpan;
    }

    // Sort by start time, then longest span first.
    // This ensures multi-day events always precede same-start single-day
    // events, producing stable row assignment as the viewport scrolls.
    final keys = eventByKey.keys.toList()
      ..sort((a, b) {
        final timeComp = eventByKey[a]!.startTime.compareTo(eventByKey[b]!.startTime);
        if (timeComp != 0) return timeComp;
        return (spanByKey[b] ?? 1).compareTo(spanByKey[a] ?? 1); // longer first
      });

    // Greedy row assignment: first available row with no overlap.
    final Map<UniqueKey, int> rowByKey = {};
    final List<int> rowLastOccupied = [];
    for (final key in keys) {
      final startIndex = startIndexByKey[key]!;
      final endIndex = startIndex + spanByKey[key]! - 1;
      int r = 0;
      while (r < rowLastOccupied.length && rowLastOccupied[r] >= startIndex) {
        r++;
      }
      rowLastOccupied.length <= r ? rowLastOccupied.add(endIndex) : rowLastOccupied[r] = endIndex;
      rowByKey[key] = r;
    }

    // When an all-day interactive slot is active, shift every event
    // down by one row so the slot always sits on top without overlap.
    final hasSlotSelection = widget.controller.slotSelectionNotifier.value is AllDaySlotSelection;
    if (hasSlotSelection) {
      for (final key in rowByKey.keys) {
        rowByKey[key] = rowByKey[key]! + 1;
      }
    }

    // Report total rows: events + optional slot row.
    widget.maxRowsNotifier?.value = rowByKey.values.isEmpty ? (hasSlotSelection ? 1 : 0) : (rowByKey.values.reduce((a, b) => a > b ? a : b) + 1);

    final List<Widget> positioned = [];
    for (final key in keys) {
      final event = eventByKey[key]!;
      final startIndex = startIndexByKey[key]!;
      final daysSpan = spanByKey[key]!;
      final row = rowByKey[key]!;

      final int endIndex = startIndex + daysSpan - 1;

      final double naturalLeft = startIndex * widget.dayWidth - offset + pad;
      final double naturalWidth = widget.dayWidth * daysSpan - pad * 2 - widget.fullDayParam.eventEndGap;
      final double naturalRight = naturalLeft + naturalWidth;

      // Visibility skip: use index-based logic for multi-day events so that
      // scroll-physics overshoot (which corrupts floating-point pixel values)
      // never causes a ghost render. Single-day events use pixel math since
      // they have no sticky-clamp behaviour and never span the viewport.
      if (daysSpan > 1) {
        if (endIndex < firstVisibleIndex) continue; // all days off-screen left
        if (startIndex > lastVisibleIndex) continue; // all days off-screen right
        if (naturalRight <= 0) continue; // last day clipped off left
      } else {
        if (naturalRight <= 0 || naturalLeft >= viewportWidth) continue;
      }

      // For multi-day events: apply left-sticky behaviour as soon as the
      // natural left edge scrolls off-screen, not only after the next whole day
      // becomes the first visible index. Keep at least one day of width so the
      // event contents are never squashed during the final-day exit.
      final double left;
      final double width;
      if (daysSpan > 1 && naturalLeft < 0) {
        final minWidth = widget.dayWidth - pad * 2 - widget.fullDayParam.eventEndGap;
        if (naturalRight >= minWidth) {
          left = 0.0;
          width = (naturalRight - left).clamp(minWidth, naturalWidth).toDouble();
        } else {
          // Keep a one-day event shape and let it scroll off with its true end.
          left = naturalRight - minWidth;
          width = minWidth;
        }
      } else {
        left = naturalLeft;
        width = naturalWidth;
      }

      final double top = rowPadding + row * (eventHeight + rowPadding);

      positioned.add(
        Positioned(
          left: left,
          top: top,
          width: width,
          height: eventHeight,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onLongPressStart: (_) {
              // Long-pressing an existing all-day event creates a new
              // AllDaySlotSelection on the event's start day.  It always
              // occupies row 0 (the top track); existing events are
              // pushed down by the bar's auto-resize system.
              final param = widget.fullDayParam.allDaySlotSelectionParam;
              final day = widget.getDayFromIndex(startIndex).withoutTime;
              final selection = AllDaySlotSelection(columnIndex: 0, initialStartDate: day, startDate: day, endDate: day, rowIndex: 0);
              widget.controller.slotSelectionNotifier.value = selection;
              param.onSlotSelectionLongPress?.call(selection);
              param.onSlotSelectionChange?.call(selection);
            },
            child:
                widget.fullDayParam.fullDayEventBuilder?.call(event, width) ??
                DefaultDayEvent(
                  height: eventHeight,
                  width: width,
                  title: event.title,
                  titleFontSize: 10,
                  description: event.description,
                  color: event.color,
                  textColor: event.textColor,
                ),
          ),
        ),
      );
    }

    if (positioned.isEmpty) return const SizedBox.shrink();
    return Stack(clipBehavior: Clip.hardEdge, children: positioned);
  }
}

class FullDayEventsWidget extends StatefulWidget {
  const FullDayEventsWidget({
    super.key,
    required this.controller,
    required this.isToday,
    required this.day,
    required this.todayColor,
    required this.fullDayParam,
    required this.columnsParam,
    required this.dayWidth,
    required this.cellGapWidthPadding,
  });

  final EventsController controller;
  final bool isToday;
  final DateTime day;
  final Color? todayColor;
  final FullDayParam fullDayParam;
  final ColumnsParam columnsParam;
  final double dayWidth;
  final double cellGapWidthPadding;

  @override
  State<FullDayEventsWidget> createState() => _FullDayEventsWidgetState();
}

class _FullDayEventsWidgetState extends State<FullDayEventsWidget> {
  List<Event>? events;

  late VoidCallback eventListener;

  @override
  void initState() {
    super.initState();
    eventListener = () => updateEvents();
    widget.controller.addListener(eventListener);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      updateEvents();
    });
  }

  @override
  void dispose() {
    super.dispose();
    widget.controller.removeListener(eventListener);
  }

  void updateEvents() {
    // Events are rendered by MultiDayEventsOverlay; nothing to update here.
  }

  @override
  Widget build(BuildContext context) {
    final param = widget.fullDayParam.allDaySlotSelectionParam;
    final canInteract = param.enableTapSlotSelection || param.enableLongPressSlotSelection;
    final width = widget.dayWidth - (widget.cellGapWidthPadding * 2);

    // Only render the background colour and optional column dividers.
    // All events are rendered by MultiDayEventsOverlay.
    final child = Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.cellGapWidthPadding),
      child: Container(
        decoration: BoxDecoration(
          color: widget.isToday && widget.todayColor != null ? widget.todayColor : widget.fullDayParam.fullDayBackgroundColor,
        ),
        child: widget.columnsParam.columns > 1 ? getColumnPainter(width) : null,
      ),
    );

    if (!canInteract) return child;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapUp: param.enableTapSlotSelection ? (details) => _onAllDayTap(details, width) : null,
      onLongPressStart: param.enableLongPressSlotSelection ? (details) => _onAllDayTap(details, width, isLongPress: true) : null,
      child: child,
    );
  }

  void _onAllDayTap(dynamic details, double innerWidth, {bool isLongPress = false}) {
    final param = widget.fullDayParam.allDaySlotSelectionParam;

    // Determine which column was tapped.
    int column = 0;
    if (details is TapUpDetails) {
      column = widget.columnsParam.getColumnIndex(innerWidth, details.localPosition.dx);
    } else if (details is LongPressStartDetails) {
      column = widget.columnsParam.getColumnIndex(innerWidth, details.localPosition.dx);
    }

    final day = widget.day.withoutTime;
    final selection = AllDaySlotSelection(columnIndex: column, initialStartDate: day, startDate: day, endDate: day);

    widget.controller.slotSelectionNotifier.value = selection;

    if (isLongPress) {
      param.onSlotSelectionLongPress?.call(selection);
    } else {
      param.onSlotSelectionTap?.call(selection);
    }
    param.onSlotSelectionChange?.call(selection);
  }

  Widget getColumnPainter(double width) {
    return SizedBox(
      width: width,
      height: widget.fullDayParam.fullDayEventsBarHeight,
      child: CustomPaint(
        foregroundPainter:
            widget.columnsParam.columnCustomPainter?.call(width, widget.columnsParam.columns) ??
            ColumnPainter(width: width, columnsParam: widget.columnsParam, lineColor: Theme.of(context).colorScheme.outlineVariant),
      ),
    );
  }
}
