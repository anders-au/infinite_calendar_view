import 'dart:core';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../controller/events_controller.dart';
import '../../events/event.dart';
import '../../events/event_arranger.dart';
import '../../events_planner.dart';
import '../../painters/events_painters.dart';
import '../../utils/extension.dart';
import '../../utils/planner_time_mapper.dart';
import '../../interactive_slot/slot_controller.dart';
import '../../interactive_slot/slot_selection.dart';

class DayWidget extends StatelessWidget {
  const DayWidget({
    super.key,
    required this.controller,
    required this.textDirection,
    required this.day,
    required this.todayColor,
    required this.cellGapWidthPadding,
    required this.plannerHeight,
    required this.heightPerMinute,
    this.plannerTimeMapper,
    required this.dayWidth,
    required this.dayEventsArranger,
    required this.dayParam,
    required this.columnsParam,
    required this.startColumnIndex,
    required this.currentHourIndicatorParam,
    required this.currentHourIndicatorColor,
    required this.offTimesParam,
    required this.showMultiDayEvents,
    this.verticalScrollController,
    this.horizontalScrollController,
    this.viewportLeftInset = 0,
    this.viewportRightInset = 0,
    this.autoScrollThreshold = 40.0,
  });

  final EventsController controller;
  final TextDirection textDirection;
  final DateTime day;
  final Color? todayColor;
  final double cellGapWidthPadding;
  final double plannerHeight;
  final double heightPerMinute;
  final PlannerTimeMapper? plannerTimeMapper;
  final double dayWidth;
  final EventArranger dayEventsArranger;
  final DayParam dayParam;
  final ColumnsParam columnsParam;
  final int startColumnIndex;
  final CurrentHourIndicatorParam currentHourIndicatorParam;
  final Color currentHourIndicatorColor;
  final OffTimesParam offTimesParam;
  final bool showMultiDayEvents;

  /// When set, the planner's vertical scroll controller — used for
  /// edge-triggered auto-scrolling during long-press slot drags.
  final ScrollController? verticalScrollController;

  /// When set, the planner's horizontal scroll controller — used for
  /// edge-triggered auto-scrolling during long-press slot drags.
  final ScrollController? horizontalScrollController;

  /// Horizontal insets to exclude from auto-scroll edge detection
  /// (time-indicator column width).
  final double viewportLeftInset;
  final double viewportRightInset;

  /// Distance in logical pixels from the viewport edge at which
  /// auto-scrolling begins during a long-press drag.
  final double autoScrollThreshold;

  PlannerTimeMapper get timeMapper => plannerTimeMapper ?? PlannerTimeMapper(heightPerMinute: heightPerMinute);

  @override
  Widget build(BuildContext context) {
    final mapper = timeMapper;
    var isToday = DateUtils.isSameDay(day, DateTime.now());
    var dayBackgroundColor = isToday && todayColor != null ? todayColor : dayParam.dayColor;
    var width = dayWidth - (cellGapWidthPadding * 2);
    var endColumnIndex =
        min(columnsParam.maxColumns != null ? startColumnIndex + columnsParam.maxColumns! : columnsParam.columns, columnsParam.columns);
    var offTimesOfDay = offTimesParam.offTimesDayRanges[day];
    var offTimesDefaultColor = context.isDarkMode ? Theme.of(context).colorScheme.surface.lighten(0.03) : const Color(0xFFF4F4F4);

    return Padding(
      padding: EdgeInsets.only(
        left: cellGapWidthPadding,
        right: cellGapWidthPadding,
        top: dayParam.dayTopPadding,
        bottom: dayParam.dayBottomPadding,
      ),
      child: GestureDetector(
        onTapUp: (details) => onSlotEvent(width, details.localPosition.dx, details.localPosition.dy, true, false, false),
        onDoubleTapDown: (details) => onSlotEvent(width, details.localPosition.dx, details.localPosition.dy, false, true, false),
        onLongPressStart: (details) => onSlotEvent(width, details.localPosition.dx, details.localPosition.dy, false, false, true),
        onLongPressMoveUpdate: (details) {
          if (dayParam.slotInteractionConfig.enableLongPressSlotSelection &&
              dayParam.slotInteractionConfig.enableShift) {
            var slotSelection = controller.slotSelectionNotifier.value;
            if (slotSelection == null || slotSelection.isAllDay) return;
            {
              final initialMinute = slotSelection.initialStartDate.totalMinutes.toDouble();
              final initialY = mapper.minuteToY(initialMinute);
              // Use extended mapping when multi-day is enabled so the
              // dragged start can cross midnight boundaries.
              final maxDuration =
                  dayParam.slotInteractionConfig.maxDurationMinutes;
              final currentMinute = maxDuration != null
                  ? mapper.yToMinuteExtended(initialY +
                      details.localOffsetFromOrigin.dy)
                  : mapper.yToMinute(
                      initialY + details.localOffsetFromOrigin.dy);
              final minutesDelta = currentMinute - initialMinute;
              final dragInc = dayParam.slotInteractionConfig.stepMinutesResolver?.call(
                    slotSelection.columnIndex,
                    slotSelection.startDateTime,
                  ) ??
                  dayParam.onSlotMinutesRound;
              var minutesDeltaRound = dayParam.onSlotRoundAlwaysBefore
                  ? dragInc * (minutesDelta / dragInc).floor()
                  : dragInc * (minutesDelta / dragInc).round();
              final daysDelta = (details.localOffsetFromOrigin.dx / dayWidth).round();
              final newStart = slotSelection.initialStartDate.addCalendarDays(daysDelta).add(Duration(minutes: minutesDeltaRound));
              controller.slotSelectionNotifier.value = CalendarSlot(
                columnIndex: slotSelection.columnIndex,
                initialStartDate: slotSelection.initialStartDate,
                startDateTime: newStart,
                endDateTime: newStart.add(Duration(minutes: slotSelection.durationInMinutes)),
              );

              // ── auto-scroll during long-press drag ──────────────────
              _applyLongPressAutoScroll(context, details.globalPosition);
            }
          }
        },
        child: Stack(
          children: [
            // offSet all days painter
            Row(
              textDirection: textDirection,
              children: [
                for (var column = startColumnIndex; column < endColumnIndex; column++)
                  Container(
                    width: columnsParam.getColumSize(width, column),
                    height: plannerHeight,
                    decoration: BoxDecoration(color: dayBackgroundColor),
                    child: CustomPaint(
                      foregroundPainter: offTimesParam.offTimesAllDaysPainter?.call(column, day, isToday, mapper.heightPerMinute,
                              offTimesParam.offTimesAllDaysRanges, offTimesParam.offTimesColor ?? offTimesDefaultColor) ??
                        OffSetAllDaysPainter(isToday, mapper.heightPerMinute, offTimesParam.offTimesAllDaysRanges,
                              offTimesParam.offTimesColor ?? offTimesDefaultColor,
                          plannerTimeMapper: mapper),
                    ),
                  ),
              ],
            ),

            // offSet particular days painter
            if (offTimesOfDay != null)
              Row(
                textDirection: textDirection,
                children: [
                  for (var column = startColumnIndex; column < endColumnIndex; column++)
                    SizedBox(
                      width: columnsParam.getColumSize(width, column),
                      height: plannerHeight,
                      child: CustomPaint(
                        foregroundPainter: offTimesParam.offTimesDayPainter?.call(column, day, isToday, mapper.heightPerMinute,
                                offTimesOfDay, offTimesParam.offTimesColor ?? offTimesDefaultColor) ??
                            OffSetAllDaysPainter(
                                false, mapper.heightPerMinute, offTimesOfDay, offTimesParam.offTimesColor ?? offTimesDefaultColor,
                                plannerTimeMapper: mapper),
                      ),
                    ),
                ],
              ),

            // lines painters
            SizedBox(
              width: width,
              height: plannerHeight,
              child: CustomPaint(
                foregroundPainter: dayParam.dayCustomPainter?.call(mapper.heightPerMinute, isToday) ??
                    LinesPainter(
                      heightPerMinute: mapper.heightPerMinute,
                      plannerTimeMapper: mapper,
                      isToday: isToday,
                      lineColor: Theme.of(context).colorScheme.outlineVariant,
                    ),
              ),
            ),

            // columns painters
            if (columnsParam.columns > 1)
              SizedBox(
                width: width,
                height: plannerHeight,
                child: CustomPaint(
                  foregroundPainter: columnsParam.columnCustomPainter?.call(
                        width,
                        min(columnsParam.maxColumns ?? columnsParam.columns, columnsParam.columns),
                      ) ??
                      ColumnPainter(
                        width: width,
                        columnsParam: columnsParam,
                        lineColor: Theme.of(context).colorScheme.outlineVariant,
                      ),
                ),
              ),

            // events
            Row(
              textDirection: textDirection,
              children: [
                for (var column = startColumnIndex; column < endColumnIndex; column++)
                  EventsListWidget(
                    // rebuild when column index change
                    key: ValueKey(column),
                    controller: controller,
                    columIndex: column,
                    day: day,
                    plannerHeight: plannerHeight - (dayParam.dayTopPadding + dayParam.dayBottomPadding),
                    heightPerMinute: mapper.heightPerMinute,
                    plannerTimeMapper: mapper,
                    dayWidth: columnsParam.getColumSize(width, column),
                    dayEventsArranger: dayEventsArranger,
                    dayParam: dayParam,
                    showMultiDayEvents: showMultiDayEvents,
                  ),
              ],
            ),

            // time line indicator
            if (currentHourIndicatorParam.currentHourIndicatorLineVisibility)
              SizedBox(
                width: width,
                height: plannerHeight,
                child: CustomPaint(
                  foregroundPainter: currentHourIndicatorParam.currentHourIndicatorCustomPainter?.call(mapper.heightPerMinute, isToday) ??
                      TimeIndicatorPainter(
                        mapper.heightPerMinute,
                        isToday,
                        currentHourIndicatorColor,
                        plannerTimeMapper: mapper,
                      ),
                ),
              ),

            // slot selection — rendered at planner level to survive
            // cross-day drags without unmounting the gesture recognizer.
          ],
        ),
      ),
    );
  }

  void onSlotEvent(
    double width,
    double dx,
    double dy,
    bool tap,
    bool doubleTap,
    bool longPress,
  ) {
    var exactDate = getExactDateTime(dy);
    var roundDate = getRoundDateTime(dy);
    var column = columnsParam.getColumnIndex(width, dx);
    var eventFunction = tap
        ? dayParam.onSlotTap
        : doubleTap
            ? dayParam.onSlotDoubleTap
            : dayParam.onSlotLongTap;
    eventFunction?.call(column, exactDate, roundDate);

    var slotInteractionConfig = dayParam.slotInteractionConfig;

    // reset slot selection
    if (controller.slotSelectionNotifier.value != null && slotInteractionConfig.clearWhenBackgroundTap) {
      controller.slotSelectionNotifier.value = null;
      slotInteractionConfig.onChanged?.call(null);
    }
    // init slot selection
    else if ((tap && slotInteractionConfig.enableTapSlotSelection) ||
        (doubleTap && slotInteractionConfig.enableDoubleTapSlotSelection) ||
        (longPress && slotInteractionConfig.enableLongPressSlotSelection)) {
      int duration =
          slotInteractionConfig.defaultDurationMinutes?.call(column, roundDate) ?? DayParam.defaultSlotDurationMinutes;
      final slot = CalendarSlot.fromTap(
        columnIndex: column,
        startDateTime: roundDate,
        durationMinutes: duration,
      );
      controller.slotSelectionNotifier.value = slot;
      slotInteractionConfig.onChanged?.call(slot);
    }
  }

  /// Applies edge-triggered auto-scroll during a long-press slot drag.
  /// Uses the same viewport detection and speed ramp as [SlotAutoScroller].
  void _applyLongPressAutoScroll(BuildContext context, Offset globalPosition) {
    if (autoScrollThreshold <= 0) return;
    final vc = verticalScrollController;
    final hc = horizontalScrollController;
    if ((vc == null || !vc.hasClients) && (hc == null || !hc.hasClients)) {
      return;
    }

    final bounds = SlotAutoScroller.viewportBoundsOf(
      context,
      leftInset: viewportLeftInset,
      rightInset: viewportRightInset,
    );
    if (bounds == null) return;

    if (SlotAutoScroller.debugAutoScroll) {
      debugPrint('[autoScroll-LP] vp=(top:${bounds.top.toStringAsFixed(0)}, '
          'btm:${bounds.bottom.toStringAsFixed(0)}, '
          'h:${bounds.height.toStringAsFixed(0)}) '
          'ptr=(${globalPosition.dx.toStringAsFixed(0)},${globalPosition.dy.toStringAsFixed(0)}) '
          'topDist=${(globalPosition.dy - bounds.top).toStringAsFixed(0)} '
          'btmDist=${(bounds.bottom - globalPosition.dy).toStringAsFixed(0)} '
          'thresh=$autoScrollThreshold');
    }

    // ── vertical ───────────────────────────────────────────────────
    if (vc != null && vc.hasClients) {
      final topDist = globalPosition.dy - bounds.top;
      final bottomDist = bounds.bottom - globalPosition.dy;
      double speed = 0;
      if (topDist < autoScrollThreshold) {
        speed = -_rampSpeed(topDist);
      } else if (bottomDist < autoScrollThreshold) {
        speed = _rampSpeed(bottomDist);
      }
      if (speed.abs() > 0.01) {
        final newOffset = (vc.offset + speed).clamp(
          vc.position.minScrollExtent,
          vc.position.maxScrollExtent,
        );
        if ((newOffset - vc.offset).abs() > 0.01) {
          if (SlotAutoScroller.debugAutoScroll) {
            debugPrint('[autoScroll-LP] VERTICAL jumpTo ${newOffset.toStringAsFixed(0)} '
                'speed=${speed.toStringAsFixed(1)}');
          }
          vc.jumpTo(newOffset);
        }
      }
    }

    // ── horizontal ─────────────────────────────────────────────────
    if (hc != null && hc.hasClients) {
      final leftDist = globalPosition.dx - bounds.left;
      final rightDist = bounds.right - globalPosition.dx;
      double speed = 0;
      if (leftDist < autoScrollThreshold) {
        speed = -_rampSpeed(leftDist);
      } else if (rightDist < autoScrollThreshold) {
        speed = _rampSpeed(rightDist);
      }
      if (speed.abs() > 0.01) {
        final newOffset = (hc.offset + speed).clamp(
          hc.position.minScrollExtent,
          hc.position.maxScrollExtent,
        );
        if ((newOffset - hc.offset).abs() > 0.01) {
          hc.jumpTo(newOffset);
        }
      }
    }
  }

  double _rampSpeed(double distanceFromEdge) {
    if (distanceFromEdge >= autoScrollThreshold) return 0;
    if (distanceFromEdge <= 0) return 8.0; // maxSpeed
    return 8.0 * (1.0 - distanceFromEdge / autoScrollThreshold);
  }

  DateTime getExactDateTime(double dy) {
    var dayMinute = timeMapper.yToMinute(dy);
    return day.withoutTime.add(Duration(minutes: dayMinute.toInt()));
  }

  // Round to nearest multiple of dayParam.onSlotMinutesRound minutes
  DateTime getRoundDateTime(double dy) {
    var dayMinute = timeMapper.yToMinute(dy);
    var dayMinuteRounded = dayParam.onSlotRoundAlwaysBefore
        ? dayParam.onSlotMinutesRound * (dayMinute / dayParam.onSlotMinutesRound).floor()
        : dayParam.onSlotMinutesRound * (dayMinute / dayParam.onSlotMinutesRound).round();
    return day.withoutTime.add(Duration(minutes: dayMinuteRounded.toInt()));
  }
}

class EventsListWidget extends StatefulWidget {
  const EventsListWidget({
    super.key,
    required this.controller,
    required this.day,
    required this.columIndex,
    required this.plannerHeight,
    required this.heightPerMinute,
    this.plannerTimeMapper,
    required this.dayWidth,
    required this.dayEventsArranger,
    required this.dayParam,
    required this.showMultiDayEvents,
  });

  final EventsController controller;
  final int columIndex;
  final DateTime day;
  final double plannerHeight;
  final double heightPerMinute;
  final PlannerTimeMapper? plannerTimeMapper;
  final double dayWidth;
  final EventArranger dayEventsArranger;
  final DayParam dayParam;
  final bool showMultiDayEvents;

  PlannerTimeMapper get timeMapper => plannerTimeMapper ?? PlannerTimeMapper(heightPerMinute: heightPerMinute);

  @override
  State<EventsListWidget> createState() => _EventsListWidgetState();
}

class _EventsListWidgetState extends State<EventsListWidget> {
  List<Event>? events;
  var organizedEvents = <OrganizedEvent>[];
  late VoidCallback eventListener;

  @override
  void initState() {
    super.initState();
    events = getDayColumnEvents();
    organizedEvents = getOrganizedEvents(events);
    eventListener = () => updateEvents();
    widget.controller.addListener(eventListener);
  }

  @override
  void dispose() {
    super.dispose();
    widget.controller.removeListener(eventListener);
  }

  List<Event>? getDayColumnEvents() {
    return widget.controller
        .getFilteredDayEvents(
          widget.day,
          returnMultiDayEvents: widget.showMultiDayEvents,
          returnFullDayEvent: false,
          returnMultiFullDayEvents: false,
        )
        ?.where((e) => e.columnIndex == widget.columIndex)
        .toList();
  }

  List<OrganizedEvent> getOrganizedEvents(List<Event>? events) {
    var arranger = widget.dayEventsArranger;
    return arranger.arrange(
      events: events ?? [],
      height: widget.plannerHeight,
      width: widget.dayWidth,
      heightPerMinute: widget.timeMapper.heightPerMinute,
    );
  }

  void updateEvents() {
    if (mounted) {
      var dayEvents = getDayColumnEvents();

      // no update if no change for current day
      if (listEquals(dayEvents, events) == false) {
        setState(() {
          events = dayEvents != null ? [...dayEvents] : null;
          organizedEvents = getOrganizedEvents(events);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.plannerHeight,
      width: widget.dayWidth,
      child: Stack(
        children: organizedEvents.map((e) => getEventWidget(e)).toList(),
      ),
    );
  }

  Widget getEventWidget(OrganizedEvent organizedEvent) {
    final mapper = widget.timeMapper;
    var left = organizedEvent.left;
    var top = mapper.minuteToY(organizedEvent.startDuration.totalMinutes.toDouble());
    var right = organizedEvent.right;
    final endMinute = organizedEvent.endDuration.totalMinutes;
    var eventBottom = mapper.minuteToY(endMinute.toDouble());
    if (mapper.cellGapHeight > 0 && endMinute > 0 && endMinute < (24 * 60) && endMinute % 60 == 0) {
      eventBottom -= mapper.cellGapHeight;
    }
    var bottom = widget.plannerHeight - eventBottom;
    var height = widget.plannerHeight - (bottom + top);
    var width = widget.dayWidth - (left + right);

    return Positioned(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      child: widget.dayParam.dayEventBuilder != null
          ? widget.dayParam.dayEventBuilder!.call(organizedEvent.event, height, width, mapper.heightPerMinute)
          : DefaultDayEvent(
              title: organizedEvent.event.title,
              description: organizedEvent.event.description,
              color: organizedEvent.event.color,
              textColor: organizedEvent.event.textColor,
              height: height,
              width: width,
            ),
    );
  }
}

class DefaultDayEvent extends StatelessWidget {
  const DefaultDayEvent({
    super.key,
    required this.height,
    required this.width,
    this.child,
    this.title,
    this.description,
    this.color = Colors.blue,
    this.textColor = Colors.white,
    this.titleFontSize = 14,
    this.descriptionFontSize = 10,
    this.horizontalPadding = 4,
    this.verticalPadding = 4,
    this.eventMargin = const EdgeInsets.all(1),
    this.roundBorderRadius = 3,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.onTapDown,
    this.onTapUp,
    this.onTapCancel,
  });

  final Widget? child;
  final String? title;
  final String? description;
  final Color color;
  final double height;
  final double width;
  final Color textColor;
  final double titleFontSize;
  final double descriptionFontSize;
  final double horizontalPadding;
  final double verticalPadding;
  final EdgeInsetsGeometry? eventMargin;
  final double roundBorderRadius;
  final GestureTapCallback? onTap;
  final GestureTapDownCallback? onTapDown;
  final GestureTapUpCallback? onTapUp;
  final GestureTapCallback? onTapCancel;
  final GestureTapCallback? onDoubleTap;
  final GestureLongPressCallback? onLongPress;

  static final minHeight = 30;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: eventMargin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(roundBorderRadius),
        child: Material(
          child: InkWell(
            onTap: onTap,
            onTapDown: onTapDown,
            onTapUp: onTapUp,
            onTapCancel: onTapCancel,
            onDoubleTap: onDoubleTap,
            onLongPress: onLongPress,
            child: Ink(
              color: color,
              width: width,
              height: height,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: height > minHeight ? verticalPadding : 0,
                ),
                child: child ??
                    Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (title?.isNotEmpty == true && height > 15)
                          Flexible(
                            child: Text(
                              title!,
                              style: TextStyle(
                                color: textColor,
                                fontSize: titleFontSize,
                              ),
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                              maxLines: height > 40 ? 2 : 1,
                            ),
                          ),
                        if (description?.isNotEmpty == true && height > 40)
                          Flexible(
                            child: Text(
                              description!,
                              style: TextStyle(color: textColor, fontSize: descriptionFontSize),
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                              maxLines: 4,
                            ),
                          ),
                      ],
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

