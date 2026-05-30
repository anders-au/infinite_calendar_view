import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:infinite_calendar_view/src/controller/events_controller.dart';
import 'package:infinite_calendar_view/src/events/event.dart';
import 'package:infinite_calendar_view/src/events_months.dart';
import 'package:infinite_calendar_view/src/utils/default_text.dart';
import 'package:infinite_calendar_view/src/utils/event_helper.dart';
import 'package:infinite_calendar_view/src/utils/extension.dart';
import 'package:infinite_calendar_view/src/widgets/month/day.dart';

class Week extends StatefulWidget {
  const Week({
    super.key,
    required this.controller,
    required this.textDirection,
    required this.weekParam,
    required this.weekHeight,
    required this.daysParam,
    required this.startOfWeek,
    required this.maxEventsShowed,
  });

  final EventsController controller;
  final TextDirection textDirection;
  final DateTime startOfWeek;
  final WeekParam weekParam;
  final double weekHeight;
  final DaysParam daysParam;
  final int maxEventsShowed;

  @override
  State<Week> createState() => _WeekState();
}

class _WeekState extends State<Week> {
  late VoidCallback eventListener;
  List<List<Event>?> weekEvents = [];
  List<List<Event?>> weekShowedEvents = [];

  EdgeInsets get dayCellMargin => widget.daysParam.dayCellMargin ?? EdgeInsets.symmetric(horizontal: widget.weekParam.daySpacing / 2);

  @override
  void initState() {
    super.initState();
    updateEvents();
    eventListener = () => updateEvents();
    widget.controller.addListener(eventListener);
  }

  @override
  void dispose() {
    super.dispose();
    widget.controller.removeListener(eventListener);
  }

  // update day events when change
  void updateEvents() {
    if (mounted) {
      var weekEvents = getWeekEvents();
      var weekShowedEvents = getShowedWeekEvents(weekEvents, widget.maxEventsShowed);
      // no update if no change for current day
      if (listEquals(weekShowedEvents, this.weekShowedEvents) == false) {
        setState(() {
          this.weekEvents = weekEvents;
          this.weekShowedEvents = weekShowedEvents;
        });
      }
    }
  }

  /// find events of week
  List<List<Event>?> getWeekEvents() {
    List<List<Event>?> eventsList = [];
    for (var day = 0; day < 7; day++) {
      eventsList.add(widget.controller.getSortedFilteredDayEvents(
        widget.startOfWeek.addCalendarDays(day),
      ));
    }
    return eventsList;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: widget.weekParam.weekDecoration ?? WeekParam.defaultWeekDecoration(context),
      child: SizedBox(
        height: widget.weekHeight,
        child: LayoutBuilder(builder: (context, constraints) {
          var width = constraints.maxWidth;
          var dayWidth = width / 7;

          return DragTarget(
            onAcceptWithDetails: (details) {
              var onDragEnd = details.data as Function(DateTime);
              var renderBox = context.findRenderObject() as RenderBox;
              var relativeOffset = renderBox.globalToLocal(Offset(details.offset.dx + dayWidth / 2, details.offset.dy));
              var dragDay = getPositionDay(relativeOffset, dayWidth);
              onDragEnd.call(dragDay);
            },
            builder: (context, candidateData, rejectedData) {
              return Stack(
                children: [
                  for (var dayOfWeek = 0; dayOfWeek < 7; dayOfWeek++) getDayCellWidget(dayOfWeek, dayWidth),
                  for (var dayOfWeek = 0; dayOfWeek < 7; dayOfWeek++)
                    for (var eventIndex = 0; eventIndex < weekShowedEvents[dayOfWeek].length; eventIndex++)
                      if (eventIndex < widget.maxEventsShowed)
                        ...getEventOrMoreEventsWidget(
                          dayOfWeek,
                          eventIndex,
                          dayWidth,
                        ),
                ],
              );
            },
          );
        }),
      ),
    );
  }

  Widget getDayCellWidget(int dayOfWeek, double dayWidth) {
    var margin = dayCellMargin;
    var horizontalPosition = getHorizontalPosition(dayOfWeek, dayWidth, margin);
    var cellWidth = dayWidth - margin.horizontal;
    var cellHeight = widget.weekHeight - margin.vertical;
    var day = widget.startOfWeek.addCalendarDays(dayOfWeek);

    return Positioned(
      left: widget.textDirection == TextDirection.ltr ? horizontalPosition : null,
      right: widget.textDirection == TextDirection.rtl ? horizontalPosition : null,
      top: margin.top,
      width: cellWidth < 0 ? 0 : cellWidth,
      height: cellHeight < 0 ? 0 : cellHeight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTapDown: widget.daysParam.onDayTapDown != null ? (_) => widget.daysParam.onDayTapDown!(day) : null,
          onTapUp: widget.daysParam.onDayTapUp != null ? (_) => widget.daysParam.onDayTapUp!(day) : null,
          child: Ink(
            decoration: widget.daysParam.dayCellDecoration,
            child: Column(
              children: [
                SizedBox(
                  height: widget.daysParam.headerHeight,
                  child: getHeaderWidget(dayOfWeek),
                ),
                SizedBox(height: widget.daysParam.spaceBetweenHeaderAndEvents),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double getHorizontalPosition(
    int dayOfWeek,
    double dayWidth,
    EdgeInsets margin,
  ) {
    return (dayOfWeek * dayWidth) + (widget.textDirection == TextDirection.ltr ? margin.left : margin.right);
  }

  DateTime getPositionDay(Offset localPosition, double dayWidth) {
    var x = localPosition.dx;
    var position = (x / dayWidth).toInt();
    var dayOfWeek = widget.textDirection == TextDirection.ltr ? position : 6 - position;
    var day = widget.startOfWeek.addCalendarDays(dayOfWeek);
    return day;
  }

  // get header of day
  Widget getHeaderWidget(int dayOfWeek) {
    var day = widget.startOfWeek.addCalendarDays(dayOfWeek);
    var isStartOfMonth = day.day == 1;
    var colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: widget.daysParam.headerHeight,
      child: widget.daysParam.dayHeaderBuilder?.call(day) ??
          DefaultMonthDayHeader(
            text:
                widget.daysParam.dayHeaderTextBuilder?.call(day) ?? (isStartOfMonth ? "${defaultMonthAbrText[day.month - 1]} 1" : day.day.toString()),
            isToday: DateUtils.isSameDay(day, DateTime.now()),
            textColor: isStartOfMonth ? colorScheme.onSurface : colorScheme.outline,
          ),
    );
  }

  /// get Event widget or "More" widget
  List<Widget> getEventOrMoreEventsWidget(
    int dayOfWeek,
    int eventIndex,
    double dayWidth,
  ) {
    var margin = dayCellMargin;
    var eventSpacing = widget.daysParam.eventSpacing;
    var eventHeight = widget.daysParam.eventHeight;
    var horizontalPosition = getHorizontalPosition(dayOfWeek, dayWidth, margin);
    var eventsLength = weekEvents[dayOfWeek]?.length ?? 0;
    var day = widget.startOfWeek.addCalendarDays(dayOfWeek);
    var eventTop =
        margin.top + widget.daysParam.headerHeight + widget.daysParam.spaceBetweenHeaderAndEvents + (eventIndex * (eventHeight + eventSpacing));

    // More widget
    var isLastSlot = eventIndex == widget.maxEventsShowed - 1;
    var notShowedEventsCount = (eventsLength - widget.maxEventsShowed) + 1;
    if (isLastSlot && notShowedEventsCount > 1) {
      return [
        Positioned(
          left: widget.textDirection == TextDirection.ltr ? horizontalPosition : null,
          right: widget.textDirection == TextDirection.rtl ? horizontalPosition : null,
          top: eventTop,
          width: (dayWidth - margin.horizontal) < 0 ? 0 : dayWidth - margin.horizontal,
          height: eventHeight,
          child: widget.daysParam.dayMoreEventsBuilder?.call(notShowedEventsCount, day) ??
              DefaultNotShowedMonthEventsWidget(
                context: context,
                eventHeight: eventHeight,
                text: "$notShowedEventsCount others",
              ),
        )
      ];
    }

    // Event widget
    var event = weekShowedEvents[dayOfWeek][eventIndex];
    var isMultiDayOtherDay = (event?.daysIndex ?? 0) > 0 && dayOfWeek > 0;
    if (event != null && !isMultiDayOtherDay) {
      // multi days events duration
      var duration = 1;
       while (true) {
        final nextDayOfWeek = dayOfWeek + duration;
        if (nextDayOfWeek >= 7) break;

        final nextEvent =
            weekShowedEvents.getOrNull(nextDayOfWeek)?.getOrNull(eventIndex);
        if (nextEvent?.uniqueId != event.uniqueId) break;

        final isLastVisibleLane = eventIndex == widget.maxEventsShowed - 1;
        if (isLastVisibleLane) {
          final nextDayRawCount = weekEvents[nextDayOfWeek]?.length ?? 0;
          final nextDayShowsMore =
              (nextDayRawCount - widget.maxEventsShowed) + 1 > 1;
          if (nextDayShowsMore) break;
        }
        duration++;
      }
      var eventWidth = (dayWidth * duration) - margin.left - margin.right;
      return [
        Positioned(
            left: widget.textDirection == TextDirection.ltr ? horizontalPosition : null,
            right: widget.textDirection == TextDirection.rtl ? horizontalPosition : null,
            top: eventTop,
            width: eventWidth < 0 ? 0 : eventWidth,
            height: eventHeight,
            child: widget.daysParam.dayEventBuilder?.call(
                  event,
                  eventWidth < 0 ? 0 : eventWidth,
                  eventHeight,
                ) ??
                DefaultMonthDayEvent(event: event))
      ];
    }

    return [];
  }
}
