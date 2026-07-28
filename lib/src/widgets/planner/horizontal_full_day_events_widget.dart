import 'package:flutter/material.dart';

import '../../../infinite_calendar_view.dart';
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

  /// Called when the all-day slot pill starts being dragged,
  /// with the [DragMode] that was activated.
  final void Function(DragMode mode)? onSlotDragStart;

  /// Called when the all-day slot pill drag ends,
  /// with the [DragMode] that was active (null if cancelled).
  final void Function(DragMode? mode)? onSlotDragEnd;

  /// Notifier holding the current all-day [CalendarSlot] for the
  /// [AllDaySlotOverlay] system.
  final ValueNotifier<CalendarSlot?>? calendarSlotNotifier;

  DateTime getDayFromIndex(int index) {
    return initialDate.addCalendarDays(
      textDirection == TextDirection.ltr ? index : -index,
    );
  }

  @override
  State<HorizontalFullDayEventsWidget> createState() =>
      _HorizontalFullDayEventsWidgetState();
}

class _HorizontalFullDayEventsWidgetState
    extends State<HorizontalFullDayEventsWidget> {
  /// Tracks the maximum number of event rows needed by the overlay.
  /// Updated every frame by [MultiDayEventsOverlay].
  final ValueNotifier<int> _maxEventRows = ValueNotifier(0);

  /// The interactive all-day slot always owns the top lane.
  final ValueNotifier<int?> _allDaySlotRow = ValueNotifier(0);
  final GlobalKey _viewportKey = GlobalKey();
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
    _allDaySlotRow.dispose();
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
    // AnimatedContainer smoothly transitions between heights.
    final barHeight = _computeBarHeight(fullDayParam);

    return AnimatedContainer(
      duration: fullDayParam.allDayBarAnimationDuration,
      curve: fullDayParam.allDayBarAnimationCurve,
      height: barHeight,
      decoration: fullDayParam.fullDayEventsBarDecoration,
      child: Row(
        textDirection: textDirection,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: timesIndicatorsWidth,
            child:
                fullDayParam.fullDayEventsBarLeftWidget ??
                Center(
                  child: Text(
                    fullDayParam.fullDayEventsBarLeftText,
                    style: TextStyle(
                      color: theme.colorScheme.outline,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  key: _viewportKey,
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
                    // Full-day events overlay â€” rendered outside the per-day
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
                          slotRowNotifier: _allDaySlotRow,
                        ),
                      ),
                    // All-day slot selection overlay â€” a pill that appears
                    // when the user taps or long-presses a day cell in the
                    // all-day bar.  Styled to match InteractiveSlot.
                    _buildAllDaySlotOverlay(
                      fullDayParam.allDaySlotInteractionConfig,
                      columnsParam,
                      fullDayParam,
                      widget.onSlotDragStart,
                      widget.onSlotDragEnd,
                      viewportWidth: constraints.maxWidth,
                      viewportKey: _viewportKey,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Dynamic bar height
  // -----------------------------------------------------------------------

  double _computeBarHeight(FullDayParam fullDayParam) {
    final rawRows = _maxEventRows.value;
    final param = fullDayParam.allDaySlotInteractionConfig;
    final canInteract =
        param.enableTapSlotSelection || param.enableLongPressSlotSelection;

    // When interactive slots are enabled, always reserve at least one
    // row so the user has a visible tap target even when no static
    // events are in the viewport.
    final effectiveRows = (canInteract && rawRows == 0) ? 1 : rawRows;

    // Cap at the configured maximum (null = no limit).
    final cappedRows = fullDayParam.maxAllDayEventRows != null
        ? effectiveRows.clamp(0, fullDayParam.maxAllDayEventRows!)
        : effectiveRows;

    // Each row: eventHeight + 2px padding.
    final rowHeight = fullDayParam.fullDayEventHeight + 2.0;
    final computed = cappedRows * rowHeight + 2.0; // top/bottom padding

    // Never shrink below the configured minimum bar height.
    if (cappedRows == 0) return fullDayParam.fullDayEventsBarHeight;
    return computed > fullDayParam.fullDayEventsBarHeight
        ? computed
        : fullDayParam.fullDayEventsBarHeight;
  }

  // -----------------------------------------------------------------------
  // All-day slot overlay (CalendarSlot system)
  // -----------------------------------------------------------------------

  Widget _buildAllDaySlotOverlay(
    SlotInteractionConfig param,
    ColumnsParam columnsParam,
    FullDayParam fullDayParam,
    void Function(DragMode mode)? onSlotDragStart,
    void Function(DragMode? mode)? onSlotDragEnd, {
    required double viewportWidth,
    required GlobalKey viewportKey,
  }) {
    final notifier = widget.calendarSlotNotifier!;

    return AnimatedBuilder(
      animation: Listenable.merge([
        notifier,
        widget.controller,
        widget.dayHorizontalController,
        _allDaySlotRow,
      ]),
      builder: (context, _) {
        final slot = notifier.value;
        if (slot == null || !slot.isAllDay) return const SizedBox.shrink();

        final innerWidth = widget.dayWidth - widget.cellGapWidthPadding * 2;
        final columnPositions = columnsParam.getColumPositions(
          innerWidth,
          slot.columnIndex,
        );

        // Wrap user config to also update the shared notifier.
        final config = SlotInteractionConfig(
          stepMinutes: param.stepMinutes,
          stepMinutesResolver: param.stepMinutesResolver,
          enableShift: param.enableShift,
          enableResizeStart: param.enableResizeStart,
          enableResizeEnd: param.enableResizeEnd,
          enableHorizontalAxis: param.enableHorizontalAxis,
          enableVerticalAxis: false, // all-day slots only move horizontally
          minDurationMinutes: 1, // 1 day minimum
          maxDurationMinutes: param.maxDurationMinutes,
          showHandles: param.showHandles,
          handleZoneSize: param.handleZoneSize,
          dragThreshold: param.dragThreshold,
          longPressDuration: param.longPressDuration,
          accentColor: param.accentColor,
          slotBorderRadius: param.slotBorderRadius,
          showDefaultSlotText: param.showDefaultSlotText,
          use24HourFormat: param.use24HourFormat,
          enableTapSlotSelection: param.enableTapSlotSelection,
          enableLongPressSlotSelection: param.enableLongPressSlotSelection,
          enableDoubleTapSlotSelection: param.enableDoubleTapSlotSelection,
          clearWhenBackgroundTap: param.clearWhenBackgroundTap,
          enableResize: param.enableResize,
          defaultDurationMinutes: param.defaultDurationMinutes,
          slotContentBuilder: param.slotContentBuilder,
          slotBuilder: param.slotBuilder,
          topHandleBuilder: param.topHandleBuilder,
          bottomHandleBuilder: param.bottomHandleBuilder,
          onChanged: (updated) {
            notifier.value = updated;
            param.onChanged?.call(updated);
          },
          onTap: (s) {
            notifier.value = s;
            param.onTap?.call(s);
          },
          onLongPress: param.onLongPress,
          onDragStart: param.onDragStart,
          onDragEnd: param.onDragEnd,
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
          viewportWidth: viewportWidth,
          viewportKey: viewportKey,
          rowNotifier: _allDaySlotRow,
          onDragStart: onSlotDragStart,
          onDragEnd: onSlotDragEnd,
          onChanged: (updated) {
            notifier.value = updated;
            param.onChanged?.call(updated);
          },
        );
      },
    );
  }
}

/// Overlay that renders ALL full-day events (single-day and multi-day) with
/// a unified greedy row-assignment algorithm so nothing overlaps. Multi-day
/// events span across day boundaries. Must be placed inside a [Positioned.fill]
/// so the [LayoutBuilder] inside receives fixed constraints from the [Stack]
/// size â€” those never change on scroll, so no layout churn occurs.
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
    this.slotRowNotifier,
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

  /// Row assigned to the interactive all-day slot.  The overlay consumes
  /// this so it can share a lane with events on non-overlapping days.
  final ValueNotifier<int?>? slotRowNotifier;

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
    // constraints come from the fixed-size Stack parent â€” they never change
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
    final lastVisibleIndex =
        firstVisibleIndex + (viewportWidth / widget.dayWidth).ceil() + 1;

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
        if (widget.fullDayParam.includeEventInAllDayLayout?.call(e) == false) {
          continue;
        }
        if (e.isSingleMidnightCrossingTimedEvent) continue;
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
      final hasSlot =
          widget.controller.slotSelectionNotifier.value?.isAllDay == true;
      _reportSlotRow(0);
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
        final endDay = DateTime(
          e.effectiveEndTime!.year,
          e.effectiveEndTime!.month,
          e.effectiveEndTime!.day,
        );
        final startDay = DateTime(
          e.startTime.year,
          e.startTime.month,
          e.startTime.day,
        );
        daysSpan = endDay.difference(startDay).inDays + 1;
      }
      spanByKey[key] = daysSpan;
    }

    // Sort by start time, then longest span first, then a stable event ID.
    // This ensures multi-day events always precede same-start single-day
    // events, producing stable row assignment as the viewport scrolls.
    final keys = eventByKey.keys.toList()
      ..sort((a, b) {
        final timeComp = eventByKey[a]!.startTime.compareTo(
          eventByKey[b]!.startTime,
        );
        if (timeComp != 0) return timeComp;
        final spanComp = (spanByKey[b] ?? 1).compareTo(spanByKey[a] ?? 1);
        if (spanComp != 0) return spanComp; // longer first
        return _layoutId(eventByKey[a]!).compareTo(_layoutId(eventByKey[b]!));
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
      rowLastOccupied.length <= r
          ? rowLastOccupied.add(endIndex)
          : rowLastOccupied[r] = endIndex;
      rowByKey[key] = r;
    }

    // The interactive all-day slot owns row zero. Recurrence-preview events
    // may share it on non-overlapping days; regular events stay below.
    final hasSlotSelection =
        widget.controller.slotSelectionNotifier.value?.isAllDay == true;
    if (hasSlotSelection) {
      final slot = widget.controller.slotSelectionNotifier.value!;
      final baseDay = widget.getDayFromIndex(0).withoutTime;
      final indexDayDelta = widget
          .getDayFromIndex(1)
          .withoutTime
          .difference(baseDay)
          .inDays;
      final slotStart =
          slot.startDateTime.withoutTime.difference(baseDay).inDays ~/
          indexDayDelta;
      final slotEnd = slotStart + slot.totalDaysSpanned - 1;

      for (final key in rowByKey.keys) {
        final eventStart = startIndexByKey[key]!;
        final eventEnd = eventStart + spanByKey[key]! - 1;
        final sharesTopRow =
            widget.fullDayParam.canShareAllDaySlotRow?.call(eventByKey[key]!) ==
                true &&
            (eventEnd < slotStart || eventStart > slotEnd);
        rowByKey[key] = sharesTopRow ? 0 : rowByKey[key]! + 1;
      }
    }

    _reportSlotRow(0);

    // Report total rows, including the reserved interactive-slot row.
    final maxEventRow = rowByKey.values.isEmpty
        ? -1
        : rowByKey.values.reduce((a, b) => a > b ? a : b);
    widget.maxRowsNotifier?.value =
        (hasSlotSelection ? (maxEventRow > 0 ? maxEventRow : 0) : maxEventRow) +
        1;

    final List<Widget> positioned = [];
    for (final key in keys) {
      final event = eventByKey[key]!;
      final startIndex = startIndexByKey[key]!;
      final daysSpan = spanByKey[key]!;
      final row = rowByKey[key]!;

      final int endIndex = startIndex + daysSpan - 1;

      final double naturalLeft = startIndex * widget.dayWidth - offset + pad;
      final double naturalWidth =
          widget.dayWidth * daysSpan -
          pad * 2 -
          widget.fullDayParam.eventEndGap;
      final double naturalRight = naturalLeft + naturalWidth;

      // Visibility skip: use index-based logic for multi-day events so that
      // scroll-physics overshoot (which corrupts floating-point pixel values)
      // never causes a ghost render. Single-day events use pixel math since
      // they have no sticky-clamp behaviour and never span the viewport.
      if (daysSpan > 1) {
        if (endIndex < firstVisibleIndex) continue; // all days off-screen left
        if (startIndex > lastVisibleIndex) {
          continue; // all days off-screen right
        }
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
      final bool isStartOffScreen;
      final bool isEndOffScreen;
      if (daysSpan > 1 && naturalLeft < 0) {
        isStartOffScreen = true;
        final minWidth =
            widget.dayWidth - pad * 2 - widget.fullDayParam.eventEndGap;
        if (naturalRight >= minWidth) {
          left = 0.0;
          width = (naturalRight - left)
              .clamp(minWidth, naturalWidth)
              .toDouble();
        } else {
          // Keep a one-day event shape and let it scroll off with its true end.
          left = naturalRight - minWidth;
          width = minWidth;
        }
        // End is off-screen when the clamped width is less than natural.
        isEndOffScreen = width < naturalWidth;
      } else {
        left = naturalLeft;
        width = naturalWidth;
        isStartOffScreen = false;
        isEndOffScreen = false;
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
              final param = widget.fullDayParam.allDaySlotInteractionConfig;
              final day = widget.getDayFromIndex(startIndex).withoutTime;
              final calSlot = CalendarSlot.allDayFromTap(
                columnIndex: 0,
                startDate: day,
                endDate: day,
              );
              widget.controller.slotSelectionNotifier.value = calSlot;
              param.onLongPress?.call(calSlot);
              param.onChanged?.call(calSlot);
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
                  hideLeftBorder: isStartOffScreen,
                  hideRightBorder: isEndOffScreen,
                ),
          ),
        ),
      );
    }

    if (positioned.isEmpty) return const SizedBox.shrink();
    return Stack(clipBehavior: Clip.hardEdge, children: positioned);
  }

  void _reportSlotRow(int row) {
    final notifier = widget.slotRowNotifier;
    if (notifier == null || notifier.value == row) return;
    notifier.value = row;
  }

  String _layoutId(Event event) {
    return widget.fullDayParam.allDayEventLayoutId?.call(event) ??
        '${event.eventType}|${event.title}|${event.description}|'
            '${event.startTime.microsecondsSinceEpoch}|'
            '${event.endTime?.microsecondsSinceEpoch}|${event.columnIndex}';
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
    final param = widget.fullDayParam.allDaySlotInteractionConfig;
    final canInteract =
        param.enableTapSlotSelection || param.enableLongPressSlotSelection;
    final width = widget.dayWidth - (widget.cellGapWidthPadding * 2);

    // Only render the background colour and optional column dividers.
    // All events are rendered by MultiDayEventsOverlay.
    final child = Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.cellGapWidthPadding),
      child: Container(
        decoration: BoxDecoration(
          color: widget.isToday && widget.todayColor != null
              ? widget.todayColor
              : widget.fullDayParam.fullDayBackgroundColor,
        ),
        child: widget.columnsParam.columns > 1 ? getColumnPainter(width) : null,
      ),
    );

    if (!canInteract) return child;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapUp: param.enableTapSlotSelection
          ? (details) => _onAllDayTap(details, width)
          : null,
      onLongPressStart: param.enableLongPressSlotSelection
          ? (details) => _onAllDayTap(details, width, isLongPress: true)
          : null,
      child: child,
    );
  }

  void _onAllDayTap(
    dynamic details,
    double innerWidth, {
    bool isLongPress = false,
  }) {
    final param = widget.fullDayParam.allDaySlotInteractionConfig;

    // Determine which column was tapped.
    int column = 0;
    if (details is TapUpDetails) {
      column = widget.columnsParam.getColumnIndex(
        innerWidth,
        details.localPosition.dx,
      );
    } else if (details is LongPressStartDetails) {
      column = widget.columnsParam.getColumnIndex(
        innerWidth,
        details.localPosition.dx,
      );
    }

    final day = widget.day.withoutTime;
    final calSlot = CalendarSlot.allDayFromTap(
      columnIndex: column,
      startDate: day,
      endDate: day,
    );

    widget.controller.slotSelectionNotifier.value = calSlot;

    if (isLongPress) {
      param.onLongPress?.call(calSlot);
    } else {
      param.onTap?.call(calSlot);
    }
    param.onChanged?.call(calSlot);
  }

  Widget getColumnPainter(double width) {
    return SizedBox(
      width: width,
      height: widget.fullDayParam.fullDayEventsBarHeight,
      child: CustomPaint(
        foregroundPainter:
            widget.columnsParam.columnCustomPainter?.call(
              width,
              widget.columnsParam.columns,
            ) ??
            ColumnPainter(
              width: width,
              columnsParam: widget.columnsParam,
              lineColor: Theme.of(context).colorScheme.outlineVariant,
            ),
      ),
    );
  }
}
