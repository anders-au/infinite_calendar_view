import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'controller/events_controller.dart';
import 'controller/events_list_view_controller.dart';
import 'events/event.dart';
import 'utils/extension.dart';
import 'utils/list/infinite_list.dart';
import 'utils/list/models/alignments.dart';
import 'widgets/details/day_details.dart';
import 'widgets/details/header_details.dart';

// ─── Binary-search lower bound ────────────────────────────────────────────────
// Returns the first index i such that sorted[i] >= target, or sorted.length if
// every element is before target.
int _lowerBound(List<DateTime> sorted, DateTime target) {
  int lo = 0, hi = sorted.length;
  while (lo < hi) {
    final mid = (lo + hi) ~/ 2;
    if (sorted[mid].isBefore(target)) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

// Returns an in-range sparse list index nearest to [target].
//
// _lowerBound can return sorted.length as an insertion-point sentinel when
// target is after the last day. In sparse mode that sentinel would create an
// empty center sliver, so map it back to the last valid item.
int _nearestSparseCenterIndex(List<DateTime> sorted, DateTime target) {
  if (sorted.isEmpty) return 0;
  final idx = _lowerBound(sorted, target);
  if (idx >= sorted.length) return sorted.length - 1;
  return idx;
}

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
    this.listViewController,
    this.hideDaysWithoutEvents = false,
    this.keepTodayVisibleWhenEmpty = false,
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

  /// Optional list view controller for programmatic navigation.
  ///
  /// When null, this widget is self-managed.
  final EventsListViewController? listViewController;

  /// When true, days with no events are omitted from the list.
  final bool hideDaysWithoutEvents;

  /// When [hideDaysWithoutEvents] is true, keep today's day entry visible
  /// even when it has no events.
  final bool keepTodayVisibleWhenEmpty;

  @override
  State createState() => EventsListState();
}

class EventsListState extends State<EventsList> {
  static const int _maxAnimatedDayDistance = 7;

  late ScrollController mainVerticalController;
  late bool _ownsMainVerticalController;
  late EventsListViewController _listViewController;
  late DateTime initialDay;
  final Object _listViewControllerOwner = Object();

  // current day
  var key = UniqueKey();
  late DateTime stickyDay;
  var currentIndex = 0;
  bool listenScroll = true;

  // ── Sparse-day state (only used when hideDaysWithoutEvents == true) ──────────
  // Sorted list of days that actually have events (plus today when
  // keepTodayVisibleWhenEmpty is set).  Instead of mapping a sequential index
  // to initialDay + index days, we map index to _sparseDays[_sparseCenterIndex
  // + index], so InfiniteList only sees non-empty day slots and never has to
  // build hundreds of zero-height items to fill the viewport.
  List<DateTime> _sparseDays = const [];
  int _sparseCenterIndex = 0; // index in _sparseDays corresponding to index 0
  VoidCallback? _sparseControllerListener;

  // ─── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    initialDay = widget.initialDate?.withoutTime ?? widget.controller.focusedDay;
    stickyDay = initialDay;
    _ownsMainVerticalController = widget.verticalController == null;
    mainVerticalController = widget.verticalController ?? ScrollController();
    _listViewController = widget.listViewController ?? EventsListViewController();
    _attachListViewController();
    if (widget.hideDaysWithoutEvents) {
      _sparseDays = _buildSparseDays();
      _sparseCenterIndex = _nearestSparseCenterIndex(_sparseDays, initialDay);
      _sparseControllerListener = _onSparseControllerUpdate;
      widget.controller.addListener(_sparseControllerListener!);
    }
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

    if (oldWidget.listViewController != widget.listViewController) {
      _listViewController.detach(owner: _listViewControllerOwner);
      _listViewController = widget.listViewController ?? EventsListViewController();
      _attachListViewController();
    }

    // Re-attach sparse listener if the controller changed.
    if (widget.hideDaysWithoutEvents) {
      if (oldWidget.controller != widget.controller) {
        if (_sparseControllerListener != null) {
          oldWidget.controller.removeListener(_sparseControllerListener!);
        }
        _sparseControllerListener = _onSparseControllerUpdate;
        widget.controller.addListener(_sparseControllerListener!);
      }

      // If mode was just enabled, set up for the first time.
      if (!oldWidget.hideDaysWithoutEvents) {
        _sparseControllerListener = _onSparseControllerUpdate;
        widget.controller.addListener(_sparseControllerListener!);
        final newDays = _buildSparseDays();
        setState(() {
          _sparseDays = newDays;
          _sparseCenterIndex = _nearestSparseCenterIndex(newDays, initialDay);
        });
      }
    } else if (oldWidget.hideDaysWithoutEvents && _sparseControllerListener != null) {
      // Mode was turned off — detach listener.
      widget.controller.removeListener(_sparseControllerListener!);
      _sparseControllerListener = null;
    }
  }

  /// Rebuilds [_sparseDays] from the controller's event map.
  ///
  /// For the list to fire [onDayChange] correctly the returned list must be
  /// sorted ascending by date.
  List<DateTime> _buildSparseDays() {
    final today = DateTime.now().withoutTime;
    final maxPrev = widget.maxPreviousDays;
    final maxNext = widget.maxNextDays;
    final earliest = maxPrev != null ? today.subtract(Duration(days: maxPrev)) : null;
    final latest = maxNext != null ? today.add(Duration(days: maxNext)) : null;

    final days = <DateTime>{};
    for (final entry in widget.controller.calendarData.dayEvents.entries) {
      final day = entry.key.withoutTime;
      if (earliest != null && day.isBefore(earliest)) continue;
      if (latest != null && day.isAfter(latest)) continue;
      if (entry.value.isEmpty) continue;
      days.add(day);
    }
    if (widget.keepTodayVisibleWhenEmpty) days.add(today);

    return days.toList()..sort();
  }

  /// Called whenever the [EventsController] notifies listeners while in
  /// sparse mode.  Rebuilds the sparse day list and forces a full list rebuild
  /// only when the set of visible days actually changed.
  void _onSparseControllerUpdate() {
    if (!mounted) return;
    final newDays = _buildSparseDays();
    if (listEquals(newDays, _sparseDays)) return;

    // Preserve scroll position: anchor on the currently sticky day.
    final newCenter = _nearestSparseCenterIndex(newDays, stickyDay);
    if (_ownsMainVerticalController) mainVerticalController.dispose();
    final newController = widget.verticalController ?? ScrollController();
    setState(() {
      key = UniqueKey();
      _sparseDays = newDays;
      _sparseCenterIndex = newCenter;
      initialDay = stickyDay;
      _ownsMainVerticalController = widget.verticalController == null;
      mainVerticalController = newController;
    });
    if (!_ownsMainVerticalController && newController.hasClients) {
      newController.jumpTo(0);
    }
  }

  void _attachListViewController() {
    _listViewController.attach(
      owner: _listViewControllerOwner,
      animateToDate: _animateToDate,
      jumpToDate: jumpToDate,
      animateToNextPage: (duration, curve) => _animateToRelativeDay(1, duration, curve),
      animateToPreviousPage: (duration, curve) => _animateToRelativeDay(-1, duration, curve),
      jumpToNextPage: () => _jumpToRelativeDay(1),
      jumpToPreviousPage: () => _jumpToRelativeDay(-1),
      isDateVisible: _isDateVisible,
      isTodayVisible: _isTodayVisible,
    );
  }

  Future<void> _animateToDate(DateTime date, Duration duration, Curve curve) async {
    final targetDay = date.withoutTime;
    if (_isDateVisible(targetDay)) {
      return;
    }

    final dayDelta = targetDay.difference(stickyDay).inDays;

    if (!mainVerticalController.hasClients || duration <= Duration.zero) {
      jumpToDate(targetDay);
      return;
    }

    if (dayDelta.abs() > _maxAnimatedDayDistance) {
      jumpToDate(targetDay);
      return;
    }

    final totalMs = duration.inMilliseconds;
    final stepMs = totalMs <= 0 ? 110 : (totalMs ~/ dayDelta.abs().clamp(1, _maxAnimatedDayDistance)).clamp(70, 150);
    final viewportExtent = mainVerticalController.position.viewportDimension.clamp(120.0, 1200.0);
    final movingForward = dayDelta > 0;
    final maxSteps = dayDelta.abs() * 5;
    var previousStickyDay = stickyDay;
    var stalledSteps = 0;

    for (var i = 0; i < maxSteps; i++) {
      if (!_isDateVisible(targetDay) && mounted && mainVerticalController.hasClients) {
        final remainingDays = targetDay.difference(stickyDay).inDays.abs();
        final double stepFactor;
        if (remainingDays <= 1) {
          stepFactor = 0.2;
        } else if (remainingDays <= 3) {
          stepFactor = 0.35;
        } else {
          stepFactor = 0.5;
        }
        final scrollDelta = viewportExtent * stepFactor;
        final nextOffset = movingForward ? (mainVerticalController.offset + scrollDelta) : (mainVerticalController.offset - scrollDelta);
        final minOffset = mainVerticalController.position.minScrollExtent;
        final maxOffset = mainVerticalController.position.maxScrollExtent;
        final clampedOffset = nextOffset.clamp(minOffset, maxOffset);

        if (clampedOffset == mainVerticalController.offset) {
          break;
        }

        await mainVerticalController.animateTo(
          clampedOffset,
          duration: Duration(milliseconds: stepMs),
          curve: curve,
        );
        await Future<void>.delayed(const Duration(milliseconds: 1));

        if (_isDateVisible(targetDay)) {
          return;
        }

        if (_hasScrolledPastTarget(targetDay, movingForward)) {
          break;
        }

        if (stickyDay == previousStickyDay) {
          stalledSteps++;
          if (stalledSteps >= 2) {
            break;
          }
        } else {
          previousStickyDay = stickyDay;
          stalledSteps = 0;
        }
      }
    }

    if (!_isDateVisible(targetDay)) {
      jumpToDate(targetDay);
    }
  }

  bool _hasScrolledPastTarget(DateTime targetDay, bool movingForward) {
    if (movingForward) {
      return stickyDay.isAfter(targetDay);
    }

    return stickyDay.isBefore(targetDay);
  }

  Future<void> _animateToRelativeDay(int dayDelta, Duration duration, Curve curve) {
    final targetDay = stickyDay.add(Duration(days: dayDelta));
    return _animateToDate(targetDay, duration, curve);
  }

  void _jumpToRelativeDay(int dayDelta) {
    jumpToDate(stickyDay.add(Duration(days: dayDelta)));
  }

  bool _isDateVisible(DateTime date) {
    final normalized = date.withoutTime;
    return stickyDay == normalized;
  }

  bool _isTodayVisible() {
    return _isDateVisible(DateTime.now());
  }

  void _notifyVisibleDayChanged(DateTime day) {
    widget.onDayChange?.call(day);
    widget.controller.updateFocusedDay(day);
  }

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      key: key,
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: widget.showWebScrollBar, dragDevices: PointerDeviceKind.values.toSet()),
      child: widget.hideDaysWithoutEvents ? _buildSparseList() : _buildDenseList(),
    );
  }

  // ── Sparse list (hideDaysWithoutEvents == true) ───────────────────────────────
  // Only the days that actually have events (plus today when
  // keepTodayVisibleWhenEmpty) are passed to InfiniteList.  The bi-directional
  // index mapping is:
  //   InfiniteList index  0  → _sparseDays[_sparseCenterIndex]
  //   InfiniteList index +n  → _sparseDays[_sparseCenterIndex + n]
  //   InfiniteList index -n  → _sparseDays[_sparseCenterIndex - n]
  //
  // Because every item has real content (non-zero height), SliverList's layout
  // loop terminates after painting a handful of viewport-filling items instead
  // of consuming all 730 day slots just to discover they are zero-height.
  Widget _buildSparseList() {
    final centerIdx = _sparseCenterIndex;
    final negCount = centerIdx;
    final posCount = _sparseDays.length - centerIdx;

    return InfiniteList(
      controller: mainVerticalController,
      direction: InfiniteListDirection.multi,
      negChildCount: negCount,
      posChildCount: posCount,
      physics: widget.verticalScrollPhysics,
      builder: (context, index) {
        final sparseIdx = centerIdx + index;
        if (sparseIdx < 0 || sparseIdx >= _sparseDays.length) {
          return InfiniteListItem(contentBuilder: (context) => const SizedBox.shrink());
        }
        return _buildDayItem(_sparseDays[sparseIdx]);
      },
    );
  }

  // ── Dense (sequential) list — original behaviour ─────────────────────────────
  Widget _buildDenseList() {
    return InfiniteList(
      controller: mainVerticalController,
      direction: InfiniteListDirection.multi,
      negChildCount: widget.maxPreviousDays,
      posChildCount: widget.maxNextDays,
      physics: widget.verticalScrollPhysics,
      builder: (context, index) {
        final day = initialDay.addCalendarDays(index).withoutTime;
        return _buildDayItem(day);
      },
    );
  }

  // ── Shared day-item builder ───────────────────────────────────────────────────
  InfiniteListItem<int> _buildDayItem(DateTime day) {
    final isToday = DateUtils.isSameDay(day, DateTime.now());
    final dayEvents = widget.controller.getSortedFilteredDayEvents(day);

    return InfiniteListItem(
      headerStateBuilder: (context, state) {
        if (state.sticky && listenScroll) {
          if (stickyDay != day) {
            stickyDay = day;
            currentIndex = state.index;
            Future(() {
              if (listenScroll == true) {
                _notifyVisibleDayChanged(stickyDay);
              }
            });
          }
        }
        return HeaderListWidget(controller: widget.controller, day: day, isToday: isToday, dayHeaderBuilder: widget.dayHeaderBuilder);
      },
      contentBuilder: (context) =>
          DayEvents(controller: widget.controller, day: day, dayEventsBuilder: widget.dayEventsBuilder, initialEvents: dayEvents),
    );
  }

  /// jump to date
  /// change initial date and redraw all list
  void jumpToDate(DateTime date) {
    if (context.mounted) {
      if (_ownsMainVerticalController) {
        mainVerticalController.dispose();
      }
      final targetDay = date.withoutTime;
      final newCenter = widget.hideDaysWithoutEvents
          ? _nearestSparseCenterIndex(_sparseDays, targetDay)
          : _sparseCenterIndex; // unused in dense mode

      setState(() {
        // change key to force rebuild
        key = UniqueKey();
        // change initial day
        initialDay = targetDay;
        stickyDay = initialDay;
        // update sparse center if applicable
        _sparseCenterIndex = newCenter;
        // reset scroll
        _ownsMainVerticalController = widget.verticalController == null;
        mainVerticalController = widget.verticalController ?? ScrollController();
      });

      _notifyVisibleDayChanged(initialDay);

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
    _listViewController.detach(owner: _listViewControllerOwner);
    if (_sparseControllerListener != null) {
      widget.controller.removeListener(_sparseControllerListener!);
    }
    if (_ownsMainVerticalController) {
      mainVerticalController.dispose();
    }
    super.dispose();
  }
}

class DayEvents extends StatefulWidget {
  const DayEvents({super.key, required this.controller, required this.day, required this.dayEventsBuilder, this.initialEvents});

  final EventsController controller;
  final DateTime day;
  final Widget Function(DateTime day, List<Event>? events)? dayEventsBuilder;
  final List<Event>? initialEvents;

  @override
  State<DayEvents> createState() => _DayEventsState();
}

class _DayEventsState extends State<DayEvents> {
  late VoidCallback eventListener;
  List<Event>? events;

  @override
  void initState() {
    super.initState();
    events = widget.initialEvents ?? widget.controller.getSortedFilteredDayEvents(widget.day);
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
