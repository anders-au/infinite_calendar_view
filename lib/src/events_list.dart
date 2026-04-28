import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'controller/events_controller.dart';
import 'events/event.dart';
import 'utils/extension.dart';
import 'utils/list/infinite_list.dart';
import 'utils/list/models/alignments.dart';
import 'widgets/details/day_details.dart';
import 'widgets/details/header_details.dart';

class EventsList extends StatefulWidget {
  const EventsList({
    super.key,
    required this.controller,
    this.initialDate,
    this.maxPreviousDays = 365,
    this.maxNextDays = 365,
    this.todayHeaderColor = const Color(0xFFf4f9fd),
    this.dayHeaderBuilder,
    this.onDayChange,
    this.dayEventsBuilder,
    this.verticalScrollPhysics = const BouncingScrollPhysics(decelerationRate: ScrollDecelerationRate.fast),
    this.verticalController,
    this.showWebScrollBar = false,
  });

  /// data controller
  final EventsController controller;

  /// initial first day
  final DateTime? initialDate;

  /// max horizontal previous days scroll
  /// Null for infinite
  final int? maxPreviousDays;

  /// max horizontal next days scroll
  /// Null for infinite
  final int? maxNextDays;

  /// events builder
  /// for listening event tap, it's possible to add gesture detector to dayEventsBuilder
  /// for loading widget, set day events to empty when day events are loaded
  /// null -> loading in progress (return shimmer or loader)
  /// empty -> no events on day (return text)
  final Widget Function(DateTime day, List<Event>? events)? dayEventsBuilder;

  /// Callback when day change during vertical scroll
  final void Function(DateTime day)? onDayChange;

  /// today day color
  /// null for no color
  final Color? todayHeaderColor;

  /// show scroll bar for web
  final bool showWebScrollBar;

  /// day builder in top bar
  final Widget Function(DateTime day, bool isToday, List<Event>? events)? dayHeaderBuilder;

  /// Vertical day scroll physics
  final ScrollPhysics verticalScrollPhysics;

  /// Optional vertical scroll controller.
  ///
  /// When null, this widget manages its own controller.
  final ScrollController? verticalController;

  @override
  State createState() => EventsListState();
}

class EventsListState extends State<EventsList> {
  late ScrollController mainVerticalController;
  late bool _ownsMainVerticalController;
  late DateTime initialDay;

  // current day
  var key = UniqueKey();
  late DateTime stickyDay;
  var currentIndex = 0;
  bool listenScroll = true;

  @override
  void initState() {
    super.initState();
    initialDay = widget.initialDate?.withoutTime ?? widget.controller.focusedDay;
    stickyDay = initialDay;
    _ownsMainVerticalController = widget.verticalController == null;
    mainVerticalController = widget.verticalController ?? ScrollController();
  }

  @override
  void didUpdateWidget(covariant EventsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.verticalController != widget.verticalController) {
      if (_ownsMainVerticalController) {
        mainVerticalController.dispose();
      }
      _ownsMainVerticalController = widget.verticalController == null;
      mainVerticalController = widget.verticalController ?? ScrollController();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      key: key,
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: widget.showWebScrollBar, dragDevices: PointerDeviceKind.values.toSet()),
      child: InfiniteList(
        controller: mainVerticalController,
        direction: InfiniteListDirection.multi,
        negChildCount: widget.maxPreviousDays,
        posChildCount: widget.maxNextDays,
        physics: widget.verticalScrollPhysics,
        builder: (context, index) {
          var day = initialDay.addCalendarDays(index).withoutTime;
          var isToday = DateUtils.isSameDay(day, DateTime.now());

          return InfiniteListItem(
            headerStateBuilder: (context, state) {
              if (state.sticky && listenScroll) {
                if (stickyDay != day) {
                  stickyDay = day;
                  currentIndex = state.index;
                  Future(() {
                    if (listenScroll == true) {
                      widget.onDayChange?.call(stickyDay);
                      widget.controller.updateFocusedDay(stickyDay);
                    }
                  });
                }
              }
              return HeaderListWidget(controller: widget.controller, day: day, isToday: isToday, dayHeaderBuilder: widget.dayHeaderBuilder);
            },
            contentBuilder: (context) => DayEvents(controller: widget.controller, day: day, dayEventsBuilder: widget.dayEventsBuilder),
          );
        },
      ),
    );
  }

  /// jump to date
  /// change initial date and redraw all list
  void jumpToDate(DateTime date) {
    if (context.mounted) {
      if (_ownsMainVerticalController) {
        mainVerticalController.dispose();
      }
      setState(() {
        // change key to force rebuild
        key = UniqueKey();
        // change initial day
        initialDay = date.withoutTime;
        // reset scroll
        _ownsMainVerticalController = widget.verticalController == null;
        mainVerticalController = widget.verticalController ?? ScrollController();
      });

      if (!_ownsMainVerticalController) {
        if (mainVerticalController.hasClients) {
          mainVerticalController.jumpTo(0);
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mainVerticalController.hasClients) {
              mainVerticalController.jumpTo(0);
            }
          });
        }
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.controller.notifyListeners();
      });
    }
  }

  @override
  void dispose() {
    if (_ownsMainVerticalController) {
      mainVerticalController.dispose();
    }
    super.dispose();
  }
}

class DayEvents extends StatefulWidget {
  const DayEvents({super.key, required this.controller, required this.day, required this.dayEventsBuilder});

  final EventsController controller;
  final DateTime day;
  final Widget Function(DateTime day, List<Event>? events)? dayEventsBuilder;

  @override
  State<DayEvents> createState() => _DayEventsState();
}

class _DayEventsState extends State<DayEvents> {
  late VoidCallback eventListener;
  List<Event>? events;

  @override
  void initState() {
    super.initState();
    events = widget.controller.getSortedFilteredDayEvents(widget.day);
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
      var dayEvents = widget.controller.getSortedFilteredDayEvents(widget.day);
      // no update if no change for current day
      if (listEquals(dayEvents, events) == false) {
        setState(() {
          events = dayEvents;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.dayEventsBuilder?.call(widget.day.withoutTime, events) ?? DefaultDayEvents(events: events);
  }
}
