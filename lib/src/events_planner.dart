import 'dart:ui';

import 'package:android_gesture_exclusion/android_gesture_exclusion.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:infinite_calendar_view/src/utils/default_text.dart';

import 'controller/events_controller.dart';
import 'controller/planner_view_controller.dart';
import 'events/event.dart';
import 'events/event_arranger.dart';
import 'events/side_events_arranger.dart';
import 'utils/extension.dart';
import 'utils/planner_time_mapper.dart';
import 'utils/list/infinite_list.dart';
import 'utils/list/models/alignments.dart';
import 'widgets/planner/day_widget.dart';
import 'widgets/planner/horizontal_days_indicator_widget.dart';
import 'widgets/planner/horizontal_full_day_events_widget.dart';
import 'widgets/planner/vertical_time_indicator_widget.dart';
import 'interactive_slot/slot_config.dart';
import 'interactive_slot/slot_overlay.dart';
import 'interactive_slot/slot_selection.dart';

class EventsPlanner extends StatefulWidget {
  const EventsPlanner({
    super.key,
    required this.controller,
    this.initialDate,
    this.daysShowed = 3,
    this.textDirection = TextDirection.ltr,
    this.maxPreviousDays = 365,
    this.maxNextDays = 365,
    this.heightPerMinute = 0.9,
    this.cellGapHeight = 0,
    this.paintGapAfterLastHour = false,
    this.cellGapWidth = 3.0,
    this.dayEventsArranger = const SideEventArranger(),
    this.onDayChange,
    this.initialVerticalScrollOffset = 0,
    this.verticalScrollController,
    this.minVerticalScrollOffset,
    this.maxVerticalScrollOffset,
    this.onVerticalScrollChange,
    this.horizontalScrollController,
    this.headerHorizontalScrollController,
    this.horizontalScrollPhysics = const BouncingScrollPhysics(decelerationRate: ScrollDecelerationRate.fast),
    this.verticalScrollPhysics,
    this.snapToDay = true,
    this.onAutomaticAdjustHorizontalScroll,
    this.dayParam = const DayParam(),
    this.columnsParam = const ColumnsParam(),
    this.timesIndicatorsParam = const TimesIndicatorsParam(),
    this.daysHeaderParam = const DaysHeaderParam(),
    this.currentHourIndicatorParam = const CurrentHourIndicatorParam(),
    this.offTimesParam = const OffTimesParam(),
    this.pinchToZoomParam = const PinchToZoomParameters(),
    this.plannerViewController,
    this.fullDayParam = const FullDayParam(),
    this.snapToWeekStart = false,
    this.startOfWeekDay = 1,
    this.snapToDaysShowed = true,
    this.autoScrollToNow = false,
    this.initialScrollHour = 8,
  });

  /// data controller
  final EventsController controller;

  /// initial first day
  final DateTime? initialDate;

  /// Number of day showing in same time
  final int daysShowed;

  // Arabic, Hindi, Hebrew text direction
  // Text direction : change position of elements and scroll direction
  final TextDirection textDirection;

  /// max horizontal previous days scroll
  /// Null for infinite
  final int? maxPreviousDays;

  /// max horizontal next days scroll
  /// /// Null for infinite
  final int? maxNextDays;

  /// Height per minute in day
  final double heightPerMinute;

  /// Vertical visual spacing between cells in planner.
  final double cellGapHeight;

  /// Horizontal visual spacing between cells in the planner.
  final double cellGapWidth;

  /// Whether to paint an additional gap after the last hour (23:00-24:00).
  final bool paintGapAfterLastHour;

  /// Arrange events position in day
  /// See SimpleEventArranger
  final EventArranger dayEventsArranger;

  /// Callback when first day (showed in planner) change during horizontal scroll
  final void Function(DateTime firstDay)? onDayChange;

  /// initial time scroll (vertical) : hour of day = heightPerMinute * $total_minutes
  final double initialVerticalScrollOffset;

  /// Optional vertical planner scroll controller.
  ///
  /// When null, this widget manages its own controller.
  final ScrollController? verticalScrollController;

  /// min time scroll (vertical) : hour of day = heightPerMinute * $total_minutes
  /// used to limit day time range (example 8->20h)
  final double? minVerticalScrollOffset;

  /// max time scroll (vertical) : hour of day = heightPerMinute * $total_minutes
  /// used to limit day time range (example 8->20h)
  final double? maxVerticalScrollOffset;

  /// call when vertical scroll change
  final void Function(double offset)? onVerticalScrollChange;

  /// Optional horizontal day scroll controller.
  ///
  /// When null, this widget manages its own controller.
  final ScrollController? horizontalScrollController;

  /// Optional horizontal controller shared by day headers and full-day events.
  ///
  /// When null, this widget manages its own controller.
  final ScrollController? headerHorizontalScrollController;

  /// Horizontal day scroll physics
  final ScrollPhysics horizontalScrollPhysics;

  /// Vertical day scroll physics
  final ScrollPhysics? verticalScrollPhysics;

  /// Automatic adjust horizontal scroll to nearest day and background
  final bool snapToDay;

  /// Automatic adjust horizontal scroll to nearest day and background
  final void Function(DateTime day)? onAutomaticAdjustHorizontalScroll;

  /// day param : day builder, padding, colors...
  final DayParam dayParam;

  /// columns param : multi columns (multi agenda) per day
  final ColumnsParam columnsParam;

  /// left time indicator (hour) parameters
  final TimesIndicatorsParam timesIndicatorsParam;

  /// days in header parameters
  final DaysHeaderParam daysHeaderParam;

  /// hour indicator (line and text) param
  final CurrentHourIndicatorParam currentHourIndicatorParam;

  /// offTimes param
  final OffTimesParam offTimesParam;

  ///  pinchToZoom parameters
  final PinchToZoomParameters pinchToZoomParam;

  /// Optional planner view controller for programmatic navigation.
  ///
  /// When null, this widget manages its own controller.
  final PlannerViewController? plannerViewController;

  // full day parameters
  final FullDayParam fullDayParam;

  /// When true and [daysShowed] == 7, horizontal scrolling snaps to
  /// week boundaries so the first visible day falls on [startOfWeekDay].
  ///
  /// Disabled during interactive-slot drags, re-applied afterward.
  /// Ignored when [daysShowed] != 7.
  ///
  /// Defaults to false.
  final bool snapToWeekStart;

  /// The weekday that marks the start of each week when
  /// [snapToWeekStart] is enabled.
  ///
  /// Uses the same convention as [DateTime.weekday]:
  ///   1 = Monday, 2 = Tuesday, ... 7 = Sunday.
  ///
  /// Clamped to 1–7. Defaults to 1 (Monday).
  final int startOfWeekDay;

  /// When true (default), both free-scrolling and programmatic
  /// navigation ([PlannerViewController.animateToDate],
  /// [PlannerViewController.jumpToDate]) snap to the nearest page
  /// boundary — a multiple of [daysShowed] anchored at [initialDate].
  ///
  /// For example, with `daysShowed: 3` and an initial date of July 1,
  /// a free scroll that stops near July 5 snaps to July 4 (the start
  /// of the July 4–6 page).  Jumping to July 5 snaps the same way.
  ///
  /// When false, free-scrolling snaps to the nearest single day,
  /// and programmatic navigation goes directly to the requested date
  /// without bracket snapping.
  ///
  /// When [snapToWeekStart] is also enabled with `daysShowed: 7`,
  /// [initialDate] is already aligned to [startOfWeekDay], so page
  /// boundaries naturally coincide with week boundaries.
  ///
  /// Disabled during interactive-slot drags, re-applied afterward.
  ///
  /// Defaults to true.
  final bool snapToDaysShowed;

  /// When true and today is within the visible day range, the planner
  /// jumps vertically to the current time (minus a 30-minute offset) on
  /// the first frame.
  ///
  /// When true but today is not visible, falls back to
  /// [initialScrollHour]. When false (default), the existing
  /// [initialVerticalScrollOffset] is used as-is.
  ///
  /// Defaults to false.
  final bool autoScrollToNow;

  /// The hour (0–23) to scroll to when [autoScrollToNow] is true and
  /// today is not visible.
  ///
  /// Clamped to 0–23. Defaults to 8 (08:00).
  final int initialScrollHour;

  /// When true, uses the new [CalendarSlot]-based interactive slot system
  /// instead of the legacy [TimedSlotSelection]/[AllDaySlotSelection] system.
  @override
  State createState() => EventsPlannerState();
}

class EventsPlannerState extends State<EventsPlanner> with TickerProviderStateMixin {
  late ScrollController mainHorizontalController;
  late ScrollController headersHorizontalController;
  final topLeftCellValueNotifier = ValueNotifier<DateTime>(DateTime.now());
  late ScrollController mainVerticalController;
  late bool _ownsMainHorizontalController;
  late bool _ownsHeadersHorizontalController;
  late bool _ownsMainVerticalController;
  late PlannerViewController _plannerViewController;
  late DateTime initialDate;
  double width = 0;
  double height = 0;
  double dayWidth = 0;
  late int currentIndex;
  late EventsController _controller;
  VoidCallback? automaticScrollAdjustListener;
  VoidCallback? _syncHorizontalControllersListener;
  VoidCallback? _dayChangingListener;
  VoidCallback? _verticalScrollChangeStopListener;
  VoidCallback? _limitVerticalScrollListener;
  late double heightPerMinute;
  late double heightPerMinuteScaleStart;
  late double mainVerticalControllerOffsetScaleStart;
  var _listenHorizontalScrollDayChange = true;
  var _hasResolvedVisibleFirstDay = false;
  var _plannerPointerDownCount = 0;
  var _isKeyboardZoomActive = false;
  var _startColumnIndex = 0;
  Drag? _headerHorizontalDrag;
  VoidCallback? _slotSelectionListener;
  bool _isSlotDragging = false;

  /// Public notifier that emits the current [DragMode] while a slot is
  /// being dragged, and null when no drag is in progress.
  ///
  /// Listen to this to react to drag state changes from outside the
  /// planner widget.  For example:
  /// ```dart
  /// plannerState.slotDragModeNotifier.addListener(() {
  ///   final mode = plannerState.slotDragModeNotifier.value;
  ///   if (mode == null) {
  ///     // drag ended
  ///   } else {
  ///     // drag in progress with given mode
  ///   }
  /// });
  /// ```
  final ValueNotifier<DragMode?> slotDragModeNotifier = ValueNotifier<DragMode?>(null);
  final Object _plannerViewControllerOwner = Object();

  /// Notifier for the new [CalendarSlot] system.  Only used when
  /// [EventsPlanner.useSlotSystem] is true.
  final ValueNotifier<CalendarSlot?> _calendarSlotNotifier = ValueNotifier<CalendarSlot?>(null);

  PlannerTimeMapper get plannerTimeMapper =>
      PlannerTimeMapper(heightPerMinute: heightPerMinute, cellGapHeight: widget.cellGapHeight, paintGapAfterLastHour: widget.paintGapAfterLastHour);

  @override
  void initState() {
    super.initState();
    heightPerMinute = widget.heightPerMinute;
    _controller = widget.controller;
    initialDate = widget.initialDate?.withoutTime ?? widget.controller.focusedDay;
    if (widget.snapToWeekStart && widget.daysShowed == 7) {
      final wsd = widget.startOfWeekDay.clamp(1, 7);
      final delta = (initialDate.weekday - wsd) % 7;
      initialDate = DateTime(initialDate.year, initialDate.month, initialDate.day - delta);
    }
    currentIndex = 0;
    _ownsMainHorizontalController = widget.horizontalScrollController == null;
    _ownsHeadersHorizontalController = widget.headerHorizontalScrollController == null;
    _ownsMainVerticalController = widget.verticalScrollController == null;

    mainHorizontalController = widget.horizontalScrollController ?? ScrollController();
    headersHorizontalController = widget.headerHorizontalScrollController ?? ScrollController();
    mainVerticalController = widget.verticalScrollController ?? ScrollController(initialScrollOffset: widget.initialVerticalScrollOffset);
    _plannerViewController = widget.plannerViewController ?? PlannerViewController();
    _attachPlannerViewController();

    // synchronize horizontal scroll between days events / full day events / days header
    if (widget.daysHeaderParam.daysHeaderVisibility || widget.fullDayParam.fullDayEventsBarVisibility) {
      _syncHorizontalControllersListener = () {
        headersHorizontalController.jumpTo(mainHorizontalController.offset);
      };
      mainHorizontalController.addListener(_syncHorizontalControllersListener!);
    }

    // ── Listen for slot dismissal to keep focused day in sync ──────────
    _slotSelectionListener = () {
      final val = _controller.slotSelectionNotifier.value;
      if (val == null && !_isSlotDragging) {
        _syncCurrentDayFromScroll();
      }
    };
    _controller.slotSelectionNotifier.addListener(_slotSelectionListener!);

    // ── Sync old → new slot model ───────────────────────────────────────
    _controller.slotSelectionNotifier.addListener(_syncToSlotModel);
    // Initial sync in case a slot was already set.
    _syncToSlotModel();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // index calculation and first day showed
      initDayChangingListener();

      // Automatic adjust horizontal scroll to nearest day
      if (widget.snapToDay) {
        automaticScrollAdjustListener = getAutomaticScrollAdjustListener();
        mainHorizontalController.position.isScrollingNotifier.addListener(automaticScrollAdjustListener!);
      }

      // init vertical scroll listener when scroll stop
      if (widget.onVerticalScrollChange != null) {
        _verticalScrollChangeStopListener = () {
          if (!mainVerticalController.position.isScrollingNotifier.value) {
            widget.onVerticalScrollChange?.call(mainVerticalController.offset);
          }
        };
        mainVerticalController.position.isScrollingNotifier.addListener(_verticalScrollChangeStopListener!);
      }

      // limit day range
      if (widget.minVerticalScrollOffset != null || widget.maxVerticalScrollOffset != null) {
        _limitVerticalScrollListener = () {
          var minOffset = widget.minVerticalScrollOffset;
          var maxOffset = widget.maxVerticalScrollOffset;
          if (_plannerPointerDownCount < 2 && !_isSlotDragging) {
            if (minOffset != null && mainVerticalController.offset < minOffset) {
              mainVerticalController.jumpTo(minOffset);
            }
            if (maxOffset != null) {
              var maxScrollExtent = mainVerticalController.position.maxScrollExtent;
              var dayOffset = plannerTimeMapper.totalDayHeight();
              var maxOffsetExtend = maxScrollExtent - (dayOffset - maxOffset);
              if (mainVerticalController.offset > maxOffsetExtend) {
                mainVerticalController.jumpTo(maxOffsetExtend);
              }
            }
          }
        };
        mainVerticalController.addListener(_limitVerticalScrollListener!);
      }

      // listen keyboard for zoom in web/desktop
      HardwareKeyboard.instance.addHandler(_handleKeyEvent);

      // auto-scroll to current time on first frame
      if (widget.autoScrollToNow) {
        final now = DateTime.now();
        final today = now.withoutTime;
        final firstDay = initialDate.withoutTime;
        final lastDay = firstDay.addCalendarDays(widget.daysShowed - 1);
        final todayVisible = !today.isBefore(firstDay) && !today.isAfter(lastDay);

        final double targetMinutes;
        if (todayVisible) {
          // Scroll to ~30 minutes ago for context.
          targetMinutes = (now.hour * 60 + now.minute - 30).clamp(0, 24 * 60).toDouble();
        } else {
          targetMinutes = widget.initialScrollHour.clamp(0, 23) * 60.0;
        }
        final rawOffset = plannerTimeMapper.minuteToY(targetMinutes) + widget.dayParam.dayTopPadding;
        _jumpToVerticalOffset(rawOffset);
      }
    });
  }

  @override
  void didUpdateWidget(covariant EventsPlanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plannerViewController != widget.plannerViewController) {
      _plannerViewController.detach(owner: _plannerViewControllerOwner);
      _plannerViewController = widget.plannerViewController ?? PlannerViewController();
      _attachPlannerViewController();
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _headerHorizontalDrag?.cancel();
    _headerHorizontalDrag = null;

    if (_slotSelectionListener != null) {
      _controller.slotSelectionNotifier.removeListener(_slotSelectionListener!);
      _slotSelectionListener = null;
    }
    _controller.slotSelectionNotifier.removeListener(_syncToSlotModel);
    if (_syncHorizontalControllersListener != null) {
      mainHorizontalController.removeListener(_syncHorizontalControllersListener!);
    }
    if (_dayChangingListener != null) {
      mainHorizontalController.removeListener(_dayChangingListener!);
    }
    if (_limitVerticalScrollListener != null) {
      mainVerticalController.removeListener(_limitVerticalScrollListener!);
    }

    if (mainHorizontalController.hasClients && automaticScrollAdjustListener != null) {
      mainHorizontalController.position.isScrollingNotifier.removeListener(automaticScrollAdjustListener!);
    }

    if (mainVerticalController.hasClients && _verticalScrollChangeStopListener != null) {
      mainVerticalController.position.isScrollingNotifier.removeListener(_verticalScrollChangeStopListener!);
    }

    if (_ownsMainHorizontalController) {
      mainHorizontalController.dispose();
    }
    if (_ownsHeadersHorizontalController) {
      headersHorizontalController.dispose();
    }
    if (_ownsMainVerticalController) {
      mainVerticalController.dispose();
    }
    _plannerViewController.detach(owner: _plannerViewControllerOwner);
    topLeftCellValueNotifier.dispose();
    _calendarSlotNotifier.dispose();
    slotDragModeNotifier.dispose();

    super.dispose();
  }

  /// listen mainHorizontalController and call onFirstDayChange when day change
  void initDayChangingListener() {
    var halfDayWidth = (dayWidth / 2);
    var scroll = mainHorizontalController;
    _dayChangingListener = () {
      if (_listenHorizontalScrollDayChange && !_isSlotDragging) {
        var halfDay = scroll.offset >= 0 ? halfDayWidth : -halfDayWidth;
        var index = ((scroll.offset + halfDay) / dayWidth).toInt();
        // only when index has changed
        if (index != currentIndex) {
          currentIndex = index;
          var currentDay = widget.textDirection == TextDirection.ltr
              ? getDayFromIndex(currentIndex)
              : getDayFromIndex(currentIndex + widget.daysShowed - 1);
          widget.onDayChange?.call(currentDay);
          widget.controller.updateFocusedDay(currentDay);
          topLeftCellValueNotifier.value = currentDay;
          _hasResolvedVisibleFirstDay = true;
        }
      }
    };
    scroll.addListener(_dayChangingListener!);
  }

  /// listen mainHorizontalController scroll stop and adjust to nearest day
  /// (or nearest week boundary when [snapToWeekStart] is enabled).
  /// call onAutomaticAdjustHorizontalScroll when end adjust
  VoidCallback getAutomaticScrollAdjustListener() {
    return () {
      // when scroll stopped
      var scroll = mainHorizontalController;
      var stopScroll = !scroll.position.isScrollingNotifier.value;
      if (_listenHorizontalScrollDayChange && stopScroll && !_isSlotDragging && _plannerPointerDownCount == 0) {
        final useWeekSnap = widget.snapToWeekStart && widget.daysShowed == 7;

        double nearestDayOffset;
        if (useWeekSnap) {
          nearestDayOffset = _snapToNearestWeekOffset(scroll.offset);
        } else if (widget.snapToDaysShowed) {
          // Snap to bracket boundary (multiple of daysShowed).
          final pageIndex = (scroll.offset / (dayWidth * widget.daysShowed)).round();
          nearestDayOffset = pageIndex * dayWidth * widget.daysShowed;
        } else {
          // Round to nearest day
          nearestDayOffset = dayWidth * (scroll.offset / dayWidth).round();
        }

        if (nearestDayOffset != scroll.offset) {
          // adjust scroll
          Future.delayed(const Duration(milliseconds: 1), () {
            scroll.animateTo(nearestDayOffset, duration: const Duration(milliseconds: 200), curve: Curves.easeIn);

            // event
            var adjustedDay = getDayFromIndex((nearestDayOffset / dayWidth).toInt());
            widget.onAutomaticAdjustHorizontalScroll?.call(adjustedDay);
          });
        }
      }
    };
  }

  /// Computes the horizontal scroll offset for the nearest valid week-start
  /// position.  The first visible day at that offset will have weekday
  /// matching [EventsPlanner.startOfWeekDay].
  double _snapToNearestWeekOffset(double currentOffset) {
    if (dayWidth == 0) return 0;
    final wsd = widget.startOfWeekDay.clamp(1, 7);
    final baseIndex = (wsd - initialDate.weekday) % 7;
    final rawIndex = currentOffset / dayWidth;
    final k = ((rawIndex - baseIndex) / 7).round();
    final snapIndex = baseIndex + k * 7;
    return snapIndex * dayWidth;
  }

  /// Snaps the horizontal scroll to the nearest valid boundary after a
  /// scroll ends (covers non-fling drags that stop without velocity).
  /// Respects [snapToWeekStart] and [snapToDaysShowed].
  void _snapToNearestDayHorizontal() {
    if (!mainHorizontalController.hasClients || dayWidth == 0) return;
    if (_isSlotDragging) return;

    final scroll = mainHorizontalController;
    final offset = scroll.offset;

    final useWeekSnap = widget.snapToWeekStart && widget.daysShowed == 7;

    double target;
    if (useWeekSnap) {
      target = _snapToNearestWeekOffset(offset);
    } else if (widget.snapToDaysShowed) {
      // Snap to bracket boundary (multiple of daysShowed).
      final pageIndex = (offset / (dayWidth * widget.daysShowed)).round();
      target = pageIndex * dayWidth * widget.daysShowed;
    } else {
      // Snap to nearest single day.
      target = dayWidth * (offset / dayWidth).round();
    }

    if ((target - offset).abs() > 0.5) {
      // Defer to next frame — calling animateTo synchronously inside a
      // ScrollEndNotification is ignored because the scroll system is
      // still tearing down the previous activity.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mainHorizontalController.hasClients) return;
        mainHorizontalController.animateTo(target, duration: const Duration(milliseconds: 200), curve: Curves.easeIn);
      });
    }
  }

  /// Snaps the horizontal scroll to the nearest valid boundary (day or
  /// bracket) that still contains [referenceDay].  Unlike
  /// [_snapToNearestDayHorizontal] which snaps from the current scroll
  /// offset, this snaps relative to a reference day so the slot stays
  /// in view.
  void _snapToBoundary(DateTime referenceDay) {
    if (!mainHorizontalController.hasClients || dayWidth == 0) return;

    final useWeekSnap = widget.snapToDaysShowed && widget.snapToWeekStart && widget.daysShowed == 7;

    double target;
    if (useWeekSnap) {
      target = _snapToNearestWeekOffset(mainHorizontalController.offset);
    } else if (widget.snapToDaysShowed) {
      // Snap to the bracket that contains referenceDay.
      target = _getBracketStartDayForTarget(referenceDay).difference(initialDate.withoutTime).inDays * dayWidth;
    } else {
      // Snap to referenceDay itself as the first visible column.
      target = referenceDay.withoutTime.difference(initialDate.withoutTime).inDays * dayWidth;
    }

    if ((target - mainHorizontalController.offset).abs() > 0.5) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mainHorizontalController.hasClients) return;
        mainHorizontalController.animateTo(target, duration: const Duration(milliseconds: 200), curve: Curves.easeIn);
      });
    }
  }

  /// Recalculates the current day index from the horizontal scroll offset
  /// and updates [currentIndex], [focusedDay], and related notifiers.
  /// Does NOT perform any scroll-snapping animation.
  void _syncCurrentDayFromScroll() {
    if (!mainHorizontalController.hasClients || dayWidth == 0) {
      return;
    }
    final scroll = mainHorizontalController;
    final halfDayWidth = dayWidth / 2;
    final halfDay = scroll.offset >= 0 ? halfDayWidth : -halfDayWidth;
    final index = ((scroll.offset + halfDay) / dayWidth).toInt();

    if (index != currentIndex) {
      currentIndex = index;
      final currentDay = widget.textDirection == TextDirection.ltr
          ? getDayFromIndex(currentIndex)
          : getDayFromIndex(currentIndex + widget.daysShowed - 1);
      widget.onDayChange?.call(currentDay);
      widget.controller.updateFocusedDay(currentDay);
      topLeftCellValueNotifier.value = currentDay;
      _hasResolvedVisibleFirstDay = true;
    }
  }

  /// Called after a slot drag ends. Scrolls the viewport so
  /// that the day containing [slotDay] is visible (or the week containing it
  /// when [snapToWeekStart] is enabled), then synchronizes the current day
  /// index (which may have become stale while auto-scroll suppressed the
  /// day-changing listener).
  Future<void> _reconcileAfterSlotDrag(DateTime slotDay) async {
    if (!mainHorizontalController.hasClients || dayWidth == 0) {
      return;
    }
    final useWeekSnap = widget.snapToWeekStart && widget.daysShowed == 7;

    DateTime targetDay;
    if (useWeekSnap) {
      final wsd = widget.startOfWeekDay.clamp(1, 7);
      final delta = (slotDay.weekday - wsd) % 7;
      targetDay = DateTime(slotDay.year, slotDay.month, slotDay.day - delta);
    } else if (widget.snapToDaysShowed) {
      // Snap to the bracket that contains the slot, so the slot stays
      // in context within its page rather than becoming the first column
      // of a new one.
      targetDay = _getBracketStartDayForTarget(slotDay);
    } else {
      targetDay = slotDay.withoutTime;
    }

    // ── skip the scroll if the slot's day is already visible ──────────
    if (_isDayAlreadyVisible(slotDay)) {
      _syncCurrentDayFromScroll();
      _snapToNearestDayHorizontal();
      return;
    }

    // ── compute the scroll offset for the target day ───────────────────
    int dayDiff = targetDay.difference(initialDate.withoutTime).inDays;
    if (widget.textDirection == TextDirection.rtl) {
      dayDiff = -dayDiff;
    }
    final targetOffset = dayDiff * dayWidth;

    final scroll = mainHorizontalController;

    // ── scroll to the target day so it is fully in view ────────────────
    if ((targetOffset - scroll.offset).abs() > 0.5) {
      // Suppress the automatic-snap listener while we drive the
      // animation ourselves so it doesn't fight us mid-flight.
      _listenHorizontalScrollDayChange = false;
      await scroll.animateTo(targetOffset, duration: const Duration(milliseconds: 200), curve: Curves.easeIn);
      _listenHorizontalScrollDayChange = true;
    }

    // ── update day tracking (now reading the final scroll position) ────
    _syncCurrentDayFromScroll();
    _snapToBoundary(targetDay);
    final adjustedDay = getDayFromIndex(dayDiff);
    widget.onAutomaticAdjustHorizontalScroll?.call(adjustedDay);
  }

  bool _handleKeyEvent(KeyEvent event) {
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;

    //  listen ctrl or cmd key to zoom in web/desktop
    if (widget.pinchToZoomParam.pinchToZoom) {
      final isModifierPressed =
          pressed.contains(LogicalKeyboardKey.controlLeft) ||
          pressed.contains(LogicalKeyboardKey.controlRight) ||
          pressed.contains(LogicalKeyboardKey.metaLeft) ||
          pressed.contains(LogicalKeyboardKey.metaRight);
      if (isModifierPressed != _isKeyboardZoomActive) {
        setState(() => _isKeyboardZoomActive = isModifierPressed);
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    var dayParam = widget.dayParam;
    var plannerHeight = plannerTimeMapper.totalDayHeight() + dayParam.dayTopPadding + dayParam.dayBottomPadding;
    var cellGapWidthPadding = widget.cellGapWidth / 2;
    var todayColor = dayParam.todayColor ?? getDefaultTodayColor(context);
    var currentHourIndicatorColor = widget.currentHourIndicatorParam.currentHourIndicatorColor ?? getDefaultHourIndicatorColor(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        width = constraints.maxWidth;
        height = constraints.maxHeight;
        var leftWidget = widget.timesIndicatorsParam.timesIndicatorsWidth;
        dayWidth = (width - leftWidget) / widget.daysShowed;
        onColumnIndexChanged(int newStartColumnIndex) {
          setState(() {
            _startColumnIndex = newStartColumnIndex;
          });
        }

        final headerWidgets = [
          // top days header
          if (widget.daysHeaderParam.daysHeaderVisibility || widget.columnsParam.columns > 1)
            getHorizontalDaysIndicatorWidget(_startColumnIndex, onColumnIndexChanged),

          // full day events
          if (widget.fullDayParam.fullDayEventsBarVisibility)
            AndroidGestureExclusionContainer(child: getHorizontalFullDayEventsWidget(cellGapWidthPadding, todayColor)),
        ];

        return Column(
          children: [
            if (headerWidgets.isNotEmpty) _buildHeaderHorizontalDragArea(Column(mainAxisSize: MainAxisSize.min, children: headerWidgets)),

            // days content
            Expanded(child: getPlannerAndTimesWidget(plannerHeight, currentHourIndicatorColor, todayColor, cellGapWidthPadding)),
          ],
        );
      },
    );
  }

  DateTime getDayFromIndex(int index) {
    return initialDate.addCalendarDays(widget.textDirection == TextDirection.ltr ? index : -index);
  }

  Color getDefaultTodayColor(BuildContext context) {
    return context.isDarkMode ? Theme.of(context).colorScheme.surface.lighten(0.03) : Theme.of(context).colorScheme.primaryContainer.lighten(0.04);
  }

  Color getDefaultHourIndicatorColor(BuildContext context) {
    return context.isDarkMode ? Theme.of(context).colorScheme.primary.lighten() : Theme.of(context).colorScheme.primary.darken();
  }

  Widget _buildHeaderHorizontalDragArea(Widget child) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: _onHeaderHorizontalDragStart,
      onHorizontalDragUpdate: _onHeaderHorizontalDragUpdate,
      onHorizontalDragEnd: _onHeaderHorizontalDragEnd,
      onHorizontalDragCancel: _onHeaderHorizontalDragCancel,
      child: child,
    );
  }

  void _onHeaderHorizontalDragStart(DragStartDetails details) {
    if (!mainHorizontalController.hasClients) {
      return;
    }
    _headerHorizontalDrag?.cancel();
    _headerHorizontalDrag = mainHorizontalController.position.drag(details, _disposeHeaderHorizontalDrag);
  }

  void _onHeaderHorizontalDragUpdate(DragUpdateDetails details) {
    _headerHorizontalDrag?.update(details);
  }

  void _onHeaderHorizontalDragEnd(DragEndDetails details) {
    _headerHorizontalDrag?.end(details);
    _headerHorizontalDrag = null;
  }

  void _onHeaderHorizontalDragCancel() {
    _headerHorizontalDrag?.cancel();
    _headerHorizontalDrag = null;
  }

  void _disposeHeaderHorizontalDrag() {
    _headerHorizontalDrag = null;
  }

  Widget getPlannerAndTimesWidget(double plannerHeight, Color currentHourIndicatorColor, Color todayColor, double cellGapWidthPadding) {
    var zoom = widget.pinchToZoomParam;
    var canZoom = zoom.pinchToZoom;
    return GestureDetector(
      onScaleStart: canZoom ? zoom.onScaleStart ?? _onScaleStart : null,
      onScaleUpdate: canZoom ? zoom.onScaleUpdate ?? _onScaleUpdate : null,
      onScaleEnd: canZoom ? zoom.onScaleEnd ?? _onScaleEnd : null,
      child: Listener(
        // zoom on web
        onPointerSignal: _isKeyboardZoomActive ? _onPointerSignal : null,
        onPointerDown: canZoom ? (event) => _onPointerDown() : null,
        onPointerCancel: canZoom ? (event) => _onPointerUp() : null,
        onPointerUp: canZoom ? (event) => _onPointerUp() : null,
        child: IgnorePointer(
          ignoring: canZoom ? _plannerPointerDownCount > 1 : false,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false, dragDevices: PointerDeviceKind.values.toSet()),
            child: CustomScrollView(
              physics: canZoom && (_plannerPointerDownCount > 1 || _isKeyboardZoomActive)
                  ? const NeverScrollableScrollPhysics()
                  : widget.verticalScrollPhysics,
              controller: mainVerticalController,
              slivers: [
                SliverList(
                  delegate: SliverChildBuilderDelegate(childCount: 1, (context, index) {
                    final isLtr = widget.textDirection == TextDirection.ltr;
                    return SizedBox(
                      height: plannerHeight,
                      child: Stack(
                        children: [
                          // day planning infinite list — positioned behind
                          // the time column so that interactive slots
                          // overflow *under* the time indicators.
                          Positioned(
                            left: isLtr ? widget.timesIndicatorsParam.timesIndicatorsWidth : 0,
                            right: isLtr ? 0 : widget.timesIndicatorsParam.timesIndicatorsWidth,
                            top: 0,
                            bottom: 0,
                            child: getPlannerWidget(todayColor, cellGapWidthPadding, plannerHeight, currentHourIndicatorColor),
                          ),
                          // left/right Timeline — rendered on top.
                          Positioned(
                            left: isLtr ? 0 : null,
                            right: isLtr ? null : 0,
                            top: 0,
                            bottom: 0,
                            width: widget.timesIndicatorsParam.timesIndicatorsWidth,
                            child: getVerticalTimeIndicatorWidget(currentHourIndicatorColor),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget getPlannerWidget(Color todayColor, double cellGapWidthPadding, double plannerHeight, Color currentHourIndicatorColor) {
    final physics = _plannerPointerDownCount > 1
        ? const NeverScrollableScrollPhysics()
        : _isSlotDragging
        ? const BouncingScrollPhysics(decelerationRate: ScrollDecelerationRate.fast)
        : DaySnappingScrollPhysics(
            pageSize: widget.snapToDaysShowed ? dayWidth * widget.daysShowed : dayWidth,
            parent: widget.horizontalScrollPhysics,
          );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        NotificationListener<ScrollEndNotification>(
          onNotification: (_) {
            _snapToNearestDayHorizontal();
            return false;
          },
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false, dragDevices: PointerDeviceKind.values.toSet()),
            child: InfiniteList(
              physics: physics,
              controller: mainHorizontalController,
              scrollDirection: Axis.horizontal,
              direction: InfiniteListDirection.multi,
              negChildCount: widget.maxPreviousDays,
              posChildCount: widget.maxNextDays,
              builder: (context, index) {
                var day = getDayFromIndex(index);
                Future(() => widget.dayParam.onDayBuild?.call(day));
                return InfiniteListItem(
                  contentBuilder: (context) {
                    return DayWidget(
                      controller: _controller,
                      textDirection: widget.textDirection,
                      day: day,
                      todayColor: todayColor,
                      cellGapWidthPadding: cellGapWidthPadding,
                      plannerHeight: plannerHeight,
                      heightPerMinute: heightPerMinute,
                      plannerTimeMapper: plannerTimeMapper,
                      dayWidth: dayWidth,
                      dayEventsArranger: widget.dayEventsArranger,
                      dayParam: widget.dayParam,
                      columnsParam: widget.columnsParam,
                      startColumnIndex: _startColumnIndex,
                      currentHourIndicatorParam: widget.currentHourIndicatorParam,
                      currentHourIndicatorColor: currentHourIndicatorColor,
                      offTimesParam: widget.offTimesParam,
                      showMultiDayEvents: !widget.fullDayParam.showMultiDayEvents,
                      verticalScrollController: mainVerticalController,
                      horizontalScrollController: mainHorizontalController,
                      viewportLeftInset: widget.textDirection == TextDirection.ltr ? widget.timesIndicatorsParam.timesIndicatorsWidth : 0,
                      viewportRightInset: widget.textDirection == TextDirection.ltr ? 0 : widget.timesIndicatorsParam.timesIndicatorsWidth,
                    );
                  },
                );
              },
            ),
          ),
        ),
        _buildSlotOverlay(cellGapWidthPadding, plannerHeight),
      ],
    );
  }

  /// New slot overlay using the [CalendarSlot] system.
  Widget _buildSlotOverlay(double cellGapWidthPadding, double plannerHeight) {
    final slot = _calendarSlotNotifier.value;
    if (slot == null) return const SizedBox.shrink();

    final paddedWidth = dayWidth - cellGapWidthPadding * 2;
    final columnPositions = widget.columnsParam.getColumPositions(paddedWidth, slot.columnIndex);

    final leftInset = widget.textDirection == TextDirection.ltr ? widget.timesIndicatorsParam.timesIndicatorsWidth : 0.0;
    final rightInset = widget.textDirection == TextDirection.ltr ? 0.0 : widget.timesIndicatorsParam.timesIndicatorsWidth;

    // Build config from existing params so the new system mirrors old
    // settings without consumers needing to provide a separate config.
    final param = widget.dayParam.slotSelectionParam;
    final config = SlotInteractionConfig(
      stepMinutes: param.dragIncrementMinutes?.call(slot.columnIndex, slot.startDateTime) ?? widget.dayParam.onSlotMinutesRound,
      enableShift: param.canDragSlotSelectionAfterShow,
      enableExtendStart: param.enableExtendStartHandle,
      enableExtendEnd: param.enableExtendEndHandle,
      enableHorizontalAxis: true,
      enableVerticalAxis: true,
      minDurationMinutes: param.minDurationMinutes,
      maxDurationMinutes: param.maxDurationMinutes,
      showHandles: param.showHandles,
      handleZoneSize: param.handleZoneSize,
      dragThreshold: param.dragThreshold,
      accentColor: param.accentColor,
      slotBorderRadius: param.slotBorderRadius,
      showDefaultSlotText: param.showDefaultSlotText,
      use24HourFormat: param.use24HourFormat,
      onChanged: (updated) {
        _calendarSlotNotifier.value = updated;
        param.onSlotSelectionChange?.call(
          updated != null
              ? TimedSlotSelection(
                  columnIndex: updated.columnIndex,
                  initialStartDate: updated.initialStartDate,
                  startDateTime: updated.startDateTime,
                  durationInMinutes: updated.durationInMinutes,
                )
              : null,
        );
      },
      onTap: (s) => param.onSlotSelectionTap?.call(
        TimedSlotSelection(
          columnIndex: s.columnIndex,
          initialStartDate: s.initialStartDate,
          startDateTime: s.startDateTime,
          durationInMinutes: s.durationInMinutes,
        ),
      ),
      onDragStart: (mode) {
        _isSlotDragging = true;
        slotDragModeNotifier.value = mode;
      },
      onDragEnd: (mode) {
        setState(() => _isSlotDragging = false);
        slotDragModeNotifier.value = null;
      },
    );

    return SlotOverlay(
      slotNotifier: _calendarSlotNotifier,
      config: config,
      timeMapper: plannerTimeMapper,
      dayWidth: dayWidth,
      plannerHeight: plannerHeight,
      dayTopPadding: widget.dayParam.dayTopPadding,
      dayBottomPadding: widget.dayParam.dayBottomPadding,
      cellGapWidthPadding: cellGapWidthPadding,
      columnPositions: columnPositions,
      initialDate: initialDate,
      scrollController: mainHorizontalController,
      verticalScrollController: mainVerticalController,
      viewportLeftInset: leftInset,
      viewportRightInset: rightInset,
      onDragEnd: (keepInView, _) {
        if (keepInView != null) {
          _reconcileAfterSlotDrag(keepInView);
        }
      },
      onChanged: (updated) {
        _calendarSlotNotifier.value = updated;
        param.onSlotSelectionChange?.call(
          updated != null
              ? TimedSlotSelection(
                  columnIndex: updated.columnIndex,
                  initialStartDate: updated.initialStartDate,
                  startDateTime: updated.startDateTime,
                  durationInMinutes: updated.durationInMinutes,
                )
              : null,
        );
      },
    );
  }

  VerticalTimeIndicatorWidget getVerticalTimeIndicatorWidget(Color currentHourIndicatorColor) {
    return VerticalTimeIndicatorWidget(
      textDirection: widget.textDirection,
      timesIndicatorsParam: widget.timesIndicatorsParam,
      heightPerMinute: heightPerMinute,
      plannerTimeMapper: plannerTimeMapper,
      currentHourIndicatorHourVisibility: widget.currentHourIndicatorParam.currentHourIndicatorHourVisibility,
      currentHourIndicatorColor: currentHourIndicatorColor,
    );
  }

  HorizontalFullDayEventsWidget getHorizontalFullDayEventsWidget(double cellGapWidthPadding, Color todayColor) {
    return HorizontalFullDayEventsWidget(
      controller: _controller,
      textDirection: widget.textDirection,
      fullDayParam: widget.fullDayParam,
      columnsParam: widget.columnsParam,
      cellGapWidthPadding: cellGapWidthPadding,
      dayHorizontalController: headersHorizontalController,
      mainContentHorizontalController: mainHorizontalController,
      maxPreviousDays: widget.maxPreviousDays,
      maxNextDays: widget.maxNextDays,
      initialDate: initialDate,
      dayWidth: dayWidth,
      todayColor: todayColor,
      timesIndicatorsWidth: widget.timesIndicatorsParam.timesIndicatorsWidth,
      onSlotDragStart: (mode) {
        _isSlotDragging = true;
        slotDragModeNotifier.value = mode;
      },
      onSlotDragEnd: (mode) {
        setState(() => _isSlotDragging = false);
        slotDragModeNotifier.value = null;
        _syncCurrentDayFromScroll();
        _snapToNearestDayHorizontal();
      },
      calendarSlotNotifier: _calendarSlotNotifier,
    );
  }

  HorizontalDaysIndicatorWidget getHorizontalDaysIndicatorWidget(int startColumnIndex, Function(int newStartColumnIndex) onColumnIndexChanged) {
    return HorizontalDaysIndicatorWidget(
      textDirection: widget.textDirection,
      daysHeaderParam: widget.daysHeaderParam,
      columnsParam: widget.columnsParam,
      startColumnIndex: startColumnIndex,
      onColumnIndexChanged: onColumnIndexChanged,
      dayHorizontalController: headersHorizontalController,
      maxPreviousDays: widget.maxPreviousDays,
      maxNextDays: widget.maxNextDays,
      initialDate: initialDate,
      dayWidth: dayWidth,
      timesIndicatorsWidth: widget.timesIndicatorsParam.timesIndicatorsWidth,
      topLeftCellValueNotifier: topLeftCellValueNotifier,
    );
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      var minZoom = widget.pinchToZoomParam.pinchToZoomMinHeightPerMinute;
      var maxZoom = widget.pinchToZoomParam.pinchToZoomMaxHeightPerMinute;
      var speed = widget.pinchToZoomParam.pinchToZoomSpeed;
      var zoom = event.scrollDelta.dy * -0.001 * speed;
      var newHeightPerMinute = heightPerMinute + zoom;

      if (minZoom <= newHeightPerMinute && newHeightPerMinute <= maxZoom) {
        final mappedOffset = _mapOffsetForNewHeightPerMinute(
          oldOffset: mainVerticalController.offset,
          oldHeightPerMinute: heightPerMinute,
          newHeightPerMinute: newHeightPerMinute,
        );
        setState(() {
          heightPerMinute = newHeightPerMinute;
          widget.pinchToZoomParam.onZoomChange?.call(heightPerMinute);
          mainVerticalController.jumpTo(mappedOffset);
        });
      }
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    if (details.pointerCount == 2) {
      heightPerMinuteScaleStart = heightPerMinute;
      mainVerticalControllerOffsetScaleStart = mainVerticalController.offset;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount == 2) {
      var speed = widget.pinchToZoomParam.pinchToZoomSpeed;
      var scale = (((details.scale - 1) * speed) + 1);
      var newHeightPerMinute = heightPerMinuteScaleStart * scale;
      var minZoom = widget.pinchToZoomParam.pinchToZoomMinHeightPerMinute;
      var maxZoom = widget.pinchToZoomParam.pinchToZoomMaxHeightPerMinute;
      if (minZoom <= newHeightPerMinute && newHeightPerMinute <= maxZoom) {
        final mappedOffset = _mapOffsetForNewHeightPerMinute(
          oldOffset: mainVerticalControllerOffsetScaleStart,
          oldHeightPerMinute: heightPerMinuteScaleStart,
          newHeightPerMinute: newHeightPerMinute,
        );
        setState(() {
          heightPerMinute = newHeightPerMinute;
          mainVerticalController.jumpTo(mappedOffset);
        });
      }
    }
  }

  double _mapOffsetForNewHeightPerMinute({required double oldOffset, required double oldHeightPerMinute, required double newHeightPerMinute}) {
    final oldMapper = PlannerTimeMapper(
      heightPerMinute: oldHeightPerMinute,
      cellGapHeight: widget.cellGapHeight,
      paintGapAfterLastHour: widget.paintGapAfterLastHour,
    );
    final newMapper = PlannerTimeMapper(
      heightPerMinute: newHeightPerMinute,
      cellGapHeight: widget.cellGapHeight,
      paintGapAfterLastHour: widget.paintGapAfterLastHour,
    );
    final minute = oldMapper.yToMinute(oldOffset);
    return newMapper.minuteToY(minute);
  }

  void _onScaleEnd(ScaleEndDetails details) {
    widget.controller.notifyListeners();
    widget.pinchToZoomParam.onZoomChange?.call(heightPerMinute);
    if (widget.snapToDay && automaticScrollAdjustListener != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mainHorizontalController.hasClients) {
          return;
        }
        mainHorizontalController.position.isScrollingNotifier.removeListener(automaticScrollAdjustListener!);
        mainHorizontalController.position.isScrollingNotifier.addListener(automaticScrollAdjustListener!);
      });
    }
  }

  void _onPointerDown() {
    setState(() {
      _plannerPointerDownCount++;
    });
  }

  void _onPointerUp() {
    setState(() {
      _plannerPointerDownCount--;
    });
  }

  void updateHeightPerMinute(double heightPerMinute) {
    _setHeightPerMinuteImmediately(heightPerMinute);
  }

  void updateVerticalScrollOffset(double verticalScrollOffset) {
    _jumpToVerticalOffset(verticalScrollOffset);
  }

  void jumpToDate(DateTime date) {
    _jumpToDate(date);
  }

  void _attachPlannerViewController() {
    _plannerViewController.attach(
      owner: _plannerViewControllerOwner,
      animateToDate: _animateToDate,
      jumpToDate: _jumpToDate,
      animateToNextPage: _animateToNextPage,
      animateToPreviousPage: _animateToPreviousPage,
      jumpToNextPage: _jumpToNextPage,
      jumpToPreviousPage: _jumpToPreviousPage,
      animateToTime: _animateToTime,
      jumpToTime: _jumpToTime,
      animateToZoom: _animateToZoom,
      jumpToZoom: _setHeightPerMinuteImmediately,
      zoomGetter: () => heightPerMinute,
      isDateVisible: _isDayAlreadyVisible,
      isTodayVisible: () => _isDayAlreadyVisible(DateTime.now()),
    );
  }

  double _dateToHorizontalOffset(DateTime date) {
    var index = date.withoutTime.getDayDifference(initialDate);
    var offset = index * dayWidth;
    if (widget.textDirection == TextDirection.rtl) {
      offset = -offset;
    }
    return offset;
  }

  int _floorDiv(int value, int divisor) {
    final quotient = value ~/ divisor;
    final remainder = value % divisor;
    if (remainder != 0 && value.isNegative) {
      return quotient - 1;
    }
    return quotient;
  }

  DateTime _getBracketStartDayForTarget(DateTime date) {
    final normalized = date.withoutTime;
    final anchor = initialDate;
    final delta = normalized.getDayDifference(anchor);
    final bracketIndex = _floorDiv(delta, widget.daysShowed);
    final result = anchor.addCalendarDays(bracketIndex * widget.daysShowed);
    return result;
  }

  bool _isDayAlreadyVisible(DateTime day) {
    final normalized = day.withoutTime;
    final firstVisibleDay = topLeftCellValueNotifier.value.withoutTime;
    final lastVisibleDay = firstVisibleDay.addCalendarDays(widget.daysShowed - 1);
    return !normalized.isBefore(firstVisibleDay) && !normalized.isAfter(lastVisibleDay);
  }

  double _timeToVerticalOffset(TimeOfDay time) {
    final minute = time.totalMinutes.toDouble();
    final rawOffset = plannerTimeMapper.minuteToY(minute) + widget.dayParam.dayTopPadding;
    return _alignVerticalOffsetToViewportAnchor(rawOffset);
  }

  double _alignVerticalOffsetToViewportAnchor(double rawOffset) {
    if (!mainVerticalController.hasClients) {
      return rawOffset;
    }
    final viewport = mainVerticalController.position.viewportDimension;
    final anchor = _plannerViewController.verticalViewportAnchor;
    return rawOffset - (viewport * anchor);
  }

  double _clampHorizontalOffset(double offset) {
    if (!mainHorizontalController.hasClients) {
      return offset;
    }
    final min = mainHorizontalController.position.minScrollExtent;
    final max = mainHorizontalController.position.maxScrollExtent;
    return offset.clamp(min, max);
  }

  double _clampVerticalOffset(double offset) {
    if (!mainVerticalController.hasClients) {
      return offset;
    }
    final min = mainVerticalController.position.minScrollExtent;
    final max = mainVerticalController.position.maxScrollExtent;
    return offset.clamp(min, max);
  }

  Future<void> _animateToDate(DateTime date, Duration duration, Curve curve) async {
    if (!context.mounted || !mainHorizontalController.hasClients || dayWidth == 0) {
      return;
    }
    // While a slot is being dragged, suppress bracket snapping so the
    // view stays pinned (same rationale as _jumpToDate above).
    if (_isSlotDragging) {
      widget.controller.updateFocusedDay(date.withoutTime);
      return;
    }
    if (_isDayAlreadyVisible(date)) {
      widget.controller.updateFocusedDay(date.withoutTime);
      return;
    }
    _listenHorizontalScrollDayChange = false;
    try {
      final targetDay = widget.snapToDaysShowed ? _getBracketStartDayForTarget(date) : date.withoutTime;
      final offset = _clampHorizontalOffset(_dateToHorizontalOffset(targetDay));
      if ((offset - mainHorizontalController.offset).abs() < 0.001) {
        return;
      }
      await mainHorizontalController.animateTo(offset, duration: duration, curve: curve);
      final day = targetDay;
      topLeftCellValueNotifier.value = day;
      _hasResolvedVisibleFirstDay = true;
      widget.controller.updateFocusedDay(day);
      widget.onDayChange?.call(day);
    } finally {
      _listenHorizontalScrollDayChange = true;
    }
  }

  void _jumpToDate(DateTime date) {
    if (!context.mounted || !mainHorizontalController.hasClients || dayWidth == 0) {
      return;
    }
    // While a slot is being dragged, suppress bracket snapping so the
    // view stays pinned.  The consumer's onSlotSelectionChange callback
    // may call jumpToDate on every onChanged tick, which would otherwise
    // cause the viewport to jump to a different bracket mid-drag.
    if (_isSlotDragging) {
      widget.controller.updateFocusedDay(date.withoutTime);
      return;
    }
    if (_isDayAlreadyVisible(date)) {
      widget.controller.updateFocusedDay(date.withoutTime);
      return;
    }
    final targetDay = widget.snapToDaysShowed ? _getBracketStartDayForTarget(date) : date.withoutTime;
    _listenHorizontalScrollDayChange = false;
    final offset = _clampHorizontalOffset(_dateToHorizontalOffset(targetDay));
    if ((offset - mainHorizontalController.offset).abs() < 0.001) {
      _listenHorizontalScrollDayChange = true;
      return;
    }
    mainHorizontalController.jumpTo(offset);
    _listenHorizontalScrollDayChange = true;
    final day = targetDay;
    topLeftCellValueNotifier.value = day;
    _hasResolvedVisibleFirstDay = true;
    widget.controller.updateFocusedDay(day);
    widget.onDayChange?.call(day);
  }

  DateTime _getPagedTargetDay(bool next) {
    final delta = next ? widget.daysShowed : -widget.daysShowed;
    return widget.controller.focusedDay.addCalendarDays(delta);
  }

  Future<void> _animateToNextPage(Duration duration, Curve curve) {
    return _animateToDate(_getPagedTargetDay(true), duration, curve);
  }

  Future<void> _animateToPreviousPage(Duration duration, Curve curve) {
    return _animateToDate(_getPagedTargetDay(false), duration, curve);
  }

  void _jumpToNextPage() {
    _jumpToDate(_getPagedTargetDay(true));
  }

  void _jumpToPreviousPage() {
    _jumpToDate(_getPagedTargetDay(false));
  }

  Future<void> _animateToTime(TimeOfDay time, Duration duration, Curve curve) async {
    if (!context.mounted) {
      return;
    }

    if (!mainVerticalController.hasClients) {
      await WidgetsBinding.instance.endOfFrame;
      if (!context.mounted || !mainVerticalController.hasClients) {
        return;
      }
    }

    final offset = _clampVerticalOffset(_timeToVerticalOffset(time));
    await mainVerticalController.animateTo(offset, duration: duration, curve: curve);
  }

  void _jumpToTime(TimeOfDay time) {
    _jumpToVerticalOffset(_timeToVerticalOffset(time));
  }

  double _clampZoom(double newHeightPerMinute) {
    return newHeightPerMinute.clamp(widget.pinchToZoomParam.pinchToZoomMinHeightPerMinute, widget.pinchToZoomParam.pinchToZoomMaxHeightPerMinute);
  }

  Future<void> _animateToZoom(double newHeightPerMinute, Duration duration, Curve curve) async {
    final target = _clampZoom(newHeightPerMinute);
    if (duration <= Duration.zero) {
      _setHeightPerMinuteImmediately(target);
      return;
    }

    final start = heightPerMinute;
    final animationController = AnimationController(vsync: this, duration: duration);
    final animation = Tween<double>(begin: start, end: target).animate(CurvedAnimation(parent: animationController, curve: curve));
    double previous = start;
    void listener() {
      final next = animation.value;
      _setHeightPerMinuteImmediately(next, oldHeightPerMinuteOverride: previous);
      previous = next;
    }

    animation.addListener(listener);
    await animationController.forward();
    animation.removeListener(listener);
    animationController.dispose();
    widget.pinchToZoomParam.onZoomChange?.call(heightPerMinute);
  }

  void _setHeightPerMinuteImmediately(double newHeightPerMinute, {double? oldHeightPerMinuteOverride}) {
    final double clamped = _clampZoom(newHeightPerMinute);
    final double oldHeight = oldHeightPerMinuteOverride ?? heightPerMinute;
    final double oldOffset = mainVerticalController.hasClients ? mainVerticalController.offset : 0;
    final double mappedOffset = _mapOffsetForNewHeightPerMinute(oldOffset: oldOffset, oldHeightPerMinute: oldHeight, newHeightPerMinute: clamped);

    setState(() {
      heightPerMinute = clamped;
      if (mainVerticalController.hasClients) {
        mainVerticalController.jumpTo(_clampVerticalOffset(mappedOffset));
      }
    });
    widget.pinchToZoomParam.onZoomChange?.call(heightPerMinute);
  }

  void _jumpToVerticalOffset(double verticalScrollOffset) {
    if (!mainVerticalController.hasClients) {
      return;
    }
    mainVerticalController.jumpTo(_clampVerticalOffset(verticalScrollOffset));
  }

  /// Syncs old [TimedSlotSelection] from the controller's notifier to the
  /// new [CalendarSlot] notifier.  Suppressed while the new system is
  /// actively dragging to avoid feedback loops with [onChanged].
  void _syncToSlotModel() {
    if (_isSlotDragging) return;
    final oldSlot = _controller.slotSelectionNotifier.value;
    if (oldSlot is TimedSlotSelection) {
      _calendarSlotNotifier.value = CalendarSlot(
        columnIndex: oldSlot.columnIndex,
        initialStartDate: oldSlot.initialStartDate,
        startDateTime: oldSlot.startDateTime,
        endDateTime: oldSlot.endDateTime,
      );
    } else if (oldSlot is AllDaySlotSelection) {
      _calendarSlotNotifier.value = CalendarSlot.allDayFromTap(
        columnIndex: oldSlot.columnIndex,
        startDate: oldSlot.startDate,
        endDate: oldSlot.endDate,
      );
    } else if (oldSlot == null) {
      _calendarSlotNotifier.value = null;
    }
  }
}

class FullDayParam {
  const FullDayParam({
    this.fullDayEventsBarVisibility = true,
    this.showMultiDayEvents = true,
    this.fullDayEventsBarHeight = 40,
    this.fullDayEventHeight = 20,
    this.fullDayEventsBarLeftText = defaultFullDayText,
    this.fullDayEventsBarLeftWidget,
    this.fullDayEventsBarDecoration = const BoxDecoration(
      border: Border(bottom: BorderSide(color: Colors.black12)),
    ),
    this.fullDayEventsBuilder,
    this.fullDayEventBuilder,
    this.fullDayBackgroundColor,
    this.eventEndGap = 0.0,
    this.maxAllDayEventRows,
    this.allDaySlotSelectionParam = const AllDaySlotSelectionParam(),
    this.allDayBarAnimationDuration = const Duration(milliseconds: 200),
    this.allDayBarAnimationCurve = Curves.easeInOut,
  });

  /// visibility of full days events
  final bool fullDayEventsBarVisibility;

  /// show multi day event (no full day) in full day
  final bool showMultiDayEvents;

  /// events days top bar height
  final double fullDayEventsBarHeight;

  /// event height
  final double fullDayEventHeight;

  /// events days top bar left widget
  final Widget? fullDayEventsBarLeftWidget;

  /// events days top bar left text
  final String fullDayEventsBarLeftText;

  /// events days top bar decoration
  final Decoration? fullDayEventsBarDecoration;

  /// full day events builder
  final Widget Function(List<Event> events, double width)? fullDayEventsBuilder;

  /// full day event builder
  final Widget Function(Event event, double width)? fullDayEventBuilder;

  /// color of background top bar
  final Color? fullDayBackgroundColor;

  /// Gap subtracted from the right edge of each event tile.
  /// Use this to prevent tiles from bleeding into the adjacent day column
  /// when [EventsPlanner.cellGapWidth] is 0.
  final double eventEndGap;

  /// Maximum number of all-day event rows the bar will display.
  /// When null (default), the bar grows to fit all visible events.
  /// Set to a specific value to cap the bar height at that many rows.
  final int? maxAllDayEventRows;

  /// Configuration for all-day slot selection (tap/long-press on the
  /// all-day bar to create an all-day event placeholder).
  /// Defaults to [AllDaySlotSelectionParam] with all features disabled.
  final AllDaySlotSelectionParam allDaySlotSelectionParam;

  /// Duration of the animated height transition when the all-day bar
  /// grows or shrinks as events enter/leave the viewport.
  /// Defaults to 200ms.
  final Duration allDayBarAnimationDuration;

  /// Curve used for the animated height transition of the all-day bar.
  /// Defaults to [Curves.easeInOut].
  final Curve allDayBarAnimationCurve;
}

// ═══════════════════════════════════════════════════════════════════════════
// AllDaySlotSelectionParam — configuration for the all-day slot selection
// pill that appears when the user taps or long-presses a day cell in the
// all-day events bar.
// ═══════════════════════════════════════════════════════════════════════════

class AllDaySlotSelectionParam {
  const AllDaySlotSelectionParam({
    this.enableTapSlotSelection = false,
    this.enableLongPressSlotSelection = false,
    this.clearWhenBackgroundTap = true,
    this.slotSelectionContentBuilder,
    this.onSlotSelectionChange,
    this.onSlotSelectionTap,
    this.onSlotSelectionLongPress,
    this.accentColor,
    this.slotBorderRadius = 8.0,
    this.showDefaultSlotText = true,
    this.enableDrag = true,
    this.enableResize = true,
    this.dragThreshold = 6.0,
  });

  /// Enable all-day slot selection when tapping a day cell in the all-day bar.
  final bool enableTapSlotSelection;

  /// Enable all-day slot selection when long-pressing a day cell.
  final bool enableLongPressSlotSelection;

  /// Clear the all-day slot selection when the user taps elsewhere
  /// (either on a day column or on the all-day bar background).
  final bool clearWhenBackgroundTap;

  /// Custom content builder for the all-day slot selection pill.
  /// When null and [showDefaultSlotText] is true, a minimal date label is shown.
  final Widget Function(AllDaySlotSelection slot)? slotSelectionContentBuilder;

  /// Called whenever the all-day slot selection changes (created, updated,
  /// or cleared).
  final void Function(AllDaySlotSelection? slot)? onSlotSelectionChange;

  /// Called when the user taps an existing all-day slot selection pill.
  final void Function(AllDaySlotSelection slot)? onSlotSelectionTap;

  /// Called when the all-day slot selection is first created via long-press.
  final void Function(AllDaySlotSelection slot)? onSlotSelectionLongPress;

  /// Accent color for the pill border and fill.
  /// Falls back to [Theme.of(context).colorScheme.secondary].
  final Color? accentColor;

  /// Border radius for the all-day slot selection pill.
  /// Defaults to 8.0, matching [SlotSelectionParam.slotBorderRadius].
  final double slotBorderRadius;

  /// Whether to show a default date label inside the pill.
  /// Defaults to true.
  final bool showDefaultSlotText;

  /// Enable drag-to-reposition on the all-day slot pill.
  /// When true, the user can drag the pill left/right to change
  /// [AllDaySlotSelection.startDate] and [AllDaySlotSelection.endDate]
  /// by whole-day increments.
  /// Defaults to true.
  final bool enableDrag;

  /// Enable left/right edge resize handles on the all-day slot pill.
  /// When true, the user can drag the left edge to adjust [startDate]
  /// and the right edge to adjust [endDate].
  /// Defaults to true.
  final bool enableResize;

  /// Minimum pointer movement in logical pixels before an all-day
  /// drag action is committed. Prevents accidental micro-drags.
  /// Defaults to 6.0.
  final double dragThreshold;
}

// ═══════════════════════════════════════════════════════════════════════════
// SlotSelection — sealed base class for timed and all-day slot selections.
// ═══════════════════════════════════════════════════════════════════════════

/// A transient UI placeholder for a slot the user is interactively creating
/// or modifying.  Always stored in [EventsController.slotSelectionNotifier]
/// which holds exactly one selection at a time.
///
/// Use `is` checks to branch on the concrete type:
/// ```dart
/// final s = controller.slotSelectionNotifier.value;
/// if (s is TimedSlotSelection) { /* time-grid slot */ }
/// if (s is AllDaySlotSelection)  { /* all-day-bar slot */ }
/// ```
sealed class SlotSelection {
  /// The column index within the day (0 if single-column).
  final int columnIndex;

  /// The date (and optionally time) where the gesture started.
  /// For [TimedSlotSelection] the time portion is meaningful;
  /// for [AllDaySlotSelection] only the date matters.
  final DateTime initialStartDate;

  const SlotSelection({required this.columnIndex, required this.initialStartDate});

  /// Whether this is an all-day selection (no time component).
  bool get isAllDay;
}

// ═══════════════════════════════════════════════════════════════════════════
// AllDaySlotSelection — the data model for an all-day slot selection.
// ═══════════════════════════════════════════════════════════════════════════

class AllDaySlotSelection extends SlotSelection {
  /// The first day of the selection (time portion is ignored).
  final DateTime startDate;

  /// The last day of the selection, inclusive.
  /// Equals [startDate] for a single-day selection.
  final DateTime endDate;

  /// Row index within the all-day bar for non-overlapping placement.
  /// 0 = top row, 1 = next row, etc.
  final int rowIndex;

  const AllDaySlotSelection({
    required super.columnIndex,
    required super.initialStartDate,
    required this.startDate,
    required this.endDate,
    this.rowIndex = 0,
  });

  @override
  bool get isAllDay => true;

  /// Number of days spanned by this selection (always ≥ 1).
  int get dayCount => endDate.withoutTime.difference(startDate.withoutTime).inDays + 1;

  /// Converts this all-day selection into a timed slot selection on
  /// [startDate] with the given [defaultStart] time and [defaultDuration].
  TimedSlotSelection toTimed({TimeOfDay defaultStart = const TimeOfDay(hour: 9, minute: 0), int defaultDuration = 60}) {
    final startDt = DateTime(startDate.year, startDate.month, startDate.day, defaultStart.hour, defaultStart.minute);
    return TimedSlotSelection(
      columnIndex: columnIndex,
      initialStartDate: initialStartDate,
      startDateTime: startDt,
      durationInMinutes: defaultDuration,
    );
  }

  /// Creates a copy with the given fields replaced.
  AllDaySlotSelection copyWith({int? columnIndex, DateTime? initialStartDate, DateTime? startDate, DateTime? endDate, int? rowIndex}) {
    return AllDaySlotSelection(
      columnIndex: columnIndex ?? this.columnIndex,
      initialStartDate: initialStartDate ?? this.initialStartDate,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      rowIndex: rowIndex ?? this.rowIndex,
    );
  }
}

class TimedSlotSelection extends SlotSelection {
  /// Current interactive slot start date (includes time).
  final DateTime startDateTime;

  /// Current interactive slot duration in minutes.
  final int durationInMinutes;

  TimedSlotSelection({required super.columnIndex, required super.initialStartDate, required this.startDateTime, required this.durationInMinutes});

  @override
  bool get isAllDay => false;

  /// The end date-time computed from [startDateTime] + [durationInMinutes].
  DateTime get endDateTime => startDateTime.add(Duration(minutes: durationInMinutes));

  /// The effective end, treating midnight (00:00:00) as the last
  /// instant of the previous day.  Use this for all day-boundary
  /// calculations — it ensures a slot ending at midnight is still
  /// considered to end within the same calendar day.
  DateTime get effectiveEndDateTime {
    final end = endDateTime;
    final isMidnight = end.hour == 0 && end.minute == 0 && end.second == 0 && end.millisecond == 0 && end.microsecond == 0;
    return isMidnight ? end.subtract(const Duration(microseconds: 1)) : end;
  }

  /// Minute-of-day for the end of this slot.
  ///
  /// Returns a value in [1, 1440].  Midnight is mapped to 1440 (bottom
  /// of the day) rather than 0 (top of the next day).  Full-day columns
  /// in the middle of a multi-day span naturally wrap to 1440 as well.
  int get endMinuteOfDay {
    final total = startDateTime.totalMinutes + durationInMinutes;
    final mod = total % PlannerTimeMapper.minutesPerDay;
    return (mod == 0 && total > 0) ? PlannerTimeMapper.minutesPerDay : mod;
  }

  /// Number of calendar days spanned by this slot, always ≥ 1.
  /// Uses [effectiveEndDateTime] so that a slot ending at midnight is
  /// still treated as single-day (midnight belongs to the current day).
  int get totalDaysSpanned => effectiveEndDateTime.withoutTime.difference(startDateTime.withoutTime).inDays + 1;

  /// Converts this timed slot into an all-day slot.
  /// The all-day slot spans from the date of [startDateTime] through the
  /// date of the slot's end time (the next day if it crosses midnight).
  AllDaySlotSelection toAllDay() {
    final startDay = startDateTime.withoutTime;
    final endDay = effectiveEndDateTime.withoutTime;
    return AllDaySlotSelection(
      columnIndex: columnIndex,
      initialStartDate: initialStartDate,
      startDate: startDay,
      endDate: endDay.isAfter(startDay) ? endDay : startDay,
    );
  }

  /// Creates a copy with the given fields replaced.
  TimedSlotSelection copyWith({int? columnIndex, DateTime? initialStartDate, DateTime? startDateTime, int? durationInMinutes}) {
    return TimedSlotSelection(
      columnIndex: columnIndex ?? this.columnIndex,
      initialStartDate: initialStartDate ?? this.initialStartDate,
      startDateTime: startDateTime ?? this.startDateTime,
      durationInMinutes: durationInMinutes ?? this.durationInMinutes,
    );
  }
}

class PinchToZoomParameters {
  const PinchToZoomParameters({
    this.pinchToZoom = true,
    this.pinchToZoomSpeed = 1,
    this.pinchToZoomMinHeightPerMinute = 0.5,
    this.pinchToZoomMaxHeightPerMinute = 2.5,
    this.onZoomChange,
    this.onScaleStart,
    this.onScaleUpdate,
    this.onScaleEnd,
  });

  /// active pinchToZoom (scale) on planner
  /// update heightPerMinute when zoom
  final bool pinchToZoom;

  /// pinchToZoom : speed of scale
  final double pinchToZoomSpeed;

  /// pinchToZoom : min possible HeightPerMinute when scale
  final double pinchToZoomMinHeightPerMinute;

  /// pinchToZoom : max possible HeightPerMinute when scale
  final double pinchToZoomMaxHeightPerMinute;

  /// call when pinchToZoom finished. Return new heightPerMinute
  final void Function(double heightPerMinute)? onZoomChange;

  /// on scale start when scale is active
  final void Function(ScaleStartDetails details)? onScaleStart;

  /// on scale update when scale is active
  final void Function(ScaleUpdateDetails details)? onScaleUpdate;

  /// on scale end when scale is active
  final void Function(ScaleEndDetails details)? onScaleEnd;
}

class CurrentHourIndicatorParam {
  const CurrentHourIndicatorParam({
    this.currentHourIndicatorCustomPainter,
    this.currentHourIndicatorLineVisibility = true,
    this.currentHourIndicatorHourVisibility = true,
    this.currentHourIndicatorColor,
  });

  /// custom day painter for current hour
  final CustomPainter Function(double heightPerMinute, bool isToday)? currentHourIndicatorCustomPainter;

  /// show current hour line and text
  final bool currentHourIndicatorLineVisibility;

  /// show current hour line and text
  final bool currentHourIndicatorHourVisibility;

  final Color? currentHourIndicatorColor;
}

class OffTimesParam {
  const OffTimesParam({
    this.offTimesAllDaysRanges = defaultOffTimesAllDaysRange,
    this.offTimesDayRanges = const {},
    this.offTimesColor,
    this.offTimesAllDaysPainter,
    this.offTimesDayPainter,
  });

  static const defaultOffTimesAllDaysRange = [
    OffTimeRange(TimeOfDay(hour: 0, minute: 0), TimeOfDay(hour: 7, minute: 0)),
    OffTimeRange(TimeOfDay(hour: 18, minute: 0), TimeOfDay(hour: 24, minute: 0)),
  ];

  /// off time range for all day
  final List<OffTimeRange> offTimesAllDaysRanges;

  /// off time range for particular day (holidays, public holiday...)
  final Map<DateTime, List<OffTimeRange>> offTimesDayRanges;

  /// off time color
  final Color? offTimesColor;

  /// off time custom painter
  final CustomPainter Function(int column, DateTime day, bool isToday, double heightPerMinute, List<OffTimeRange> ranges, Color color)?
  offTimesAllDaysPainter;

  /// off time on day custom painter
  final CustomPainter Function(int column, DateTime day, bool isToday, double heightPerMinute, List<OffTimeRange> ranges, Color color)?
  offTimesDayPainter;
}

class OffTimeRange {
  const OffTimeRange(this.start, this.end);

  final TimeOfDay start;
  final TimeOfDay end;
}

class DaysHeaderParam {
  const DaysHeaderParam({
    this.daysHeaderVisibility = true,
    this.daysHeaderHeight = 40.0,
    this.startOfWeekDay = 7,
    this.daysHeaderColor,
    this.daysHeaderForegroundColor,
    this.dayHeaderBuilder,
    this.dayHeaderTextBuilder,
    this.topLeftCellBuilder,
  });

  /// visibility of days top bar
  final bool daysHeaderVisibility;

  /// days top bar height
  final double daysHeaderHeight;

  /// start day of week : 1 = monday, 7 = sunday
  final int startOfWeekDay;

  /// day top bar background color
  final Color? daysHeaderColor;

  /// day top bar foreground color
  final Color? daysHeaderForegroundColor;

  /// day builder in top bar
  final Widget Function(DateTime day, bool isToday)? dayHeaderBuilder;

  /// day text builder
  final String Function(DateTime day)? dayHeaderTextBuilder;

  /// top left cell builder
  final Widget Function(DateTime day)? topLeftCellBuilder;
}

class TimesIndicatorsParam {
  const TimesIndicatorsParam({this.timesIndicatorsWidth = 60.0, this.timesIndicatorsHorizontalPadding = 4.0, this.timesIndicatorsCustomPainter});

  /// width of left times bar
  final double timesIndicatorsWidth;

  /// horizontal padding of left times bar
  final double timesIndicatorsHorizontalPadding;

  /// custom times painter
  final CustomPainter Function(double heightPerMinute)? timesIndicatorsCustomPainter;
}

class ColumnsParam {
  const ColumnsParam({
    this.columns = 1,
    this.maxColumns = 3,
    this.columnsLabels = const [],
    this.columnsColors = const [],
    this.columnsForegroundColors,
    this.columnsWidthRatio,
    this.columnHeaderBuilder,
    this.columnCustomPainter,
    this.previousColumnsIcon,
    this.nextColumnsIcon,
  });

  /// number of columns per day
  final int columns;

  /// max number of columns per day : show arrow if columns > maxColumns
  final int? maxColumns;

  /// label of column showed in header
  final List<String> columnsLabels;

  /// background color of column showed in header
  final List<Color> columnsColors;

  final List<Color>? columnsForegroundColors;

  /// ratio of dayWidth of each column
  final List<double>? columnsWidthRatio;

  /// left icon to change displayed columns
  final Icon? previousColumnsIcon;

  /// right icon to change displayed columns
  final Icon? nextColumnsIcon;

  /// column custom builder in top bar
  final Widget Function(DateTime day, bool isToday, int columIndex, double columnWidth)? columnHeaderBuilder;

  /// custom day painter for paint verticals lines
  final CustomPainter Function(double width, int colum)? columnCustomPainter;

  double getColumSize(double dayWidth, int columnIndex) {
    var columnWidthRatio = columnsWidthRatio?[columnIndex];
    return columnWidthRatio != null ? dayWidth * columnWidthRatio : dayWidth / columns;
  }

  /// return column position in day width
  /// [0] = startOffset
  /// [1] = endOffset
  List<double> getColumPositions(double dayWidth, int columnIndex) {
    var startSize = 0.0;
    for (var column = 0; column < columnIndex; column++) {
      startSize += getColumSize(dayWidth, column);
    }
    return [startSize, startSize + getColumSize(dayWidth, columnIndex)];
  }

  int getColumnIndex(double dayWidth, double dx) {
    var totalWidth = 0.0;
    for (var column = 0; column < columns; column++) {
      var columnSize = getColumSize(dayWidth, column);
      if (totalWidth <= dx && dx < totalWidth + columnSize) {
        return column;
      }
      totalWidth += columnSize;
    }
    return columns - 1;
  }
}

class DayParam {
  const DayParam({
    this.todayColor,
    this.dayColor,
    this.dayTopPadding = 10,
    this.dayBottomPadding = 20,
    this.dayCustomPainter,
    this.dayEventBuilder,
    this.onSlotMinutesRound = 30,
    this.onSlotRoundAlwaysBefore = false,
    this.onSlotTap,
    this.onSlotLongTap,
    this.onSlotDoubleTap,
    this.onDayBuild,
    this.slotSelectionParam = const SlotSelectionParam(),
  });

  static int defaultSlotSelectionDurationInMinutes = 60;

  /// today day top padding (before scroll)
  final double dayTopPadding;

  /// today day bottom padding (after scroll)
  final double dayBottomPadding;

  /// event when horizontal scroll and day planner are build
  final void Function(DateTime day)? onDayBuild;

  /// today day color
  /// null for no color
  final Color? todayColor;

  /// day background color
  final Color? dayColor;

  /// custom day painter for paint horizontal lines
  final CustomPainter Function(double heightPerMinute, bool isToday)? dayCustomPainter;

  /// event builder
  /// for listening event tap, it's possible to add gesture detector to dayEventBuilder
  /// example : dayEventBuilder : (event, height, width) => DefaultDayEvent(height: height, width: width, onTap...)
  /// or GestureDetector(child: DefaultEventWidget(...));
  final Widget Function(Event event, double height, double width, double heightPerMinute)? dayEventBuilder;

  /// round date to nearest minutes date
  final int onSlotMinutesRound;

  /// always round to the nearest previous minute
  final bool onSlotRoundAlwaysBefore;

  /// event when tap on free slot on day
  final void Function(int columnIndex, DateTime exactDateTime, DateTime roundDateTime)? onSlotTap;

  /// event when long tap on free slot on day
  final void Function(int columnIndex, DateTime exactDateTime, DateTime roundDateTime)? onSlotLongTap;

  /// event when double tap on free slot on day
  final void Function(int columnIndex, DateTime exactDateTime, DateTime roundDateTime)? onSlotDoubleTap;

  // Interactive slot selection parameters
  final SlotSelectionParam slotSelectionParam;
}

class SlotSelectionParam {
  const SlotSelectionParam({
    this.enableTapSlotSelection = false,
    this.enableLongPressSlotSelection = false,
    this.enableDoubleTapSlotSelection = false,
    this.clearWhenBackgroundTap = true,
    this.canDragSlotSelectionAfterShow = true,
    this.slotSelectionDefaultDurationInMinutes,
    this.dragIncrementMinutes,
    this.slotSelectionContentBuilder,
    this.slotSelectionBuilder,
    this.onSlotSelectionChange,
    this.onSlotSelectionTap,
    this.onSlotSelectionLongPress,
    this.enableSlotSelectionResize = true,
    this.enableExtendStartHandle = true,
    this.enableExtendEndHandle = true,
    this.slotSelectionTopHandleBuilder,
    this.slotSelectionBottomHandleBuilder,
    this.accentColor,
    this.showHandles = true,
    this.handleZoneSize = 20.0,
    this.dragThreshold = 6.0,
    this.slotBorderRadius = 8.0,
    this.showDefaultSlotText = true,
    this.use24HourFormat = true,
    this.maxDurationMinutes,
    this.minDurationMinutes = 15,
  });

  /// enable interactive slot selection when tap on day slot
  final bool enableTapSlotSelection;

  /// enable interactive slot selection when long press on day slot
  final bool enableLongPressSlotSelection;

  /// enable interactive slot selection when double tap on day slot
  final bool enableDoubleTapSlotSelection;

  /// clear slot selection when background tap
  final bool clearWhenBackgroundTap;

  /// can re-drag slot selection when it show with long press
  final bool canDragSlotSelectionAfterShow;

  /// default duration in minutes of interactive slot selection
  final int Function(int columnIndex, DateTime date)? slotSelectionDefaultDurationInMinutes;

  /// Rounding increment in minutes used during drag/resize operations on
  /// the interactive slot.  When set, this overrides [DayParam.onSlotMinutesRound]
  /// for drag/resize gestures, letting the slot snap to coarser or finer
  /// intervals while dragging than the tap-rounding uses.
  ///
  /// Accepts the same signature as [slotSelectionDefaultDurationInMinutes]
  /// so the increment can vary by column or date.
  ///
  /// When null (the default), [DayParam.onSlotMinutesRound] is used for
  /// both tap-rounding and drag-rounding.
  final int Function(int columnIndex, DateTime date)? dragIncrementMinutes;

  /// interactive slot selection content in default InteractiveSlot
  final Widget Function(TimedSlotSelection slot)? slotSelectionContentBuilder;

  /// interactive slot selection builder
  final Widget Function(
    TimedSlotSelection slot,
    double dayWidth,
    DayParam dayParam,
    ColumnsParam columnsParam,
    double heightPerMinute,
    void Function(TimedSlotSelection? updatedSlot) onChanged,
  )?
  slotSelectionBuilder;

  /// event when tap on interactive slot
  final void Function(TimedSlotSelection? slot)? onSlotSelectionChange;

  /// event when tap on interactive slot
  final void Function(TimedSlotSelection slot)? onSlotSelectionTap;

  /// event when long press on interactive slot
  final void Function(TimedSlotSelection slot)? onSlotSelectionLongPress;

  /// enable interactive slot selection top and bottom handle for resize
  final bool enableSlotSelectionResize;

  /// Enable the start (top) drag handle independently.
  /// When false, the start handle is hidden and non-interactive even if
  /// [enableSlotSelectionResize] is true.  Defaults to true.
  final bool enableExtendStartHandle;

  /// Enable the end (bottom) drag handle independently.
  /// When false, the end handle is hidden and non-interactive even if
  /// [enableSlotSelectionResize] is true.  Defaults to true.
  final bool enableExtendEndHandle;

  /// interactive slot selection top handle builder (for resize)
  final Widget Function()? slotSelectionTopHandleBuilder;

  /// interactive slot selection bottom handle builder (for resize)
  final Widget Function()? slotSelectionBottomHandleBuilder;

  /// Color used for the left accent bar and resize handles.
  /// Defaults to the theme's primary color.
  final Color? accentColor;

  /// Whether to show the Google Calendar style handle indicators
  /// (small pill shapes at top and bottom).
  final bool showHandles;

  /// Fixed pixel height of the top and bottom resize zones.
  /// The middle zone (slot height - 2 * [handleZoneSize]) is the drag zone.
  /// Defaults to 14.0 pixels.
  final double handleZoneSize;

  /// Minimum pointer movement in logical pixels before a drag action is
  /// committed. Prevents accidental micro-drags. Defaults to 6.0.
  final double dragThreshold;

  /// Border radius for the slot selection pill. Defaults to 8.0.
  final double slotBorderRadius;

  /// Whether to show the default time/duration text inside the slot.
  /// When false, only a colored fill with a border is shown.
  /// Defaults to true.
  final bool showDefaultSlotText;

  /// Whether to use 24-hour format for the default slot text.
  /// When false, 12-hour format with AM/PM is used.
  /// Defaults to true (24-hour format).
  final bool use24HourFormat;

  /// Maximum duration in minutes a timed slot selection may have.
  ///
  /// When set, the slot cannot exceed this total duration, regardless
  /// of how many calendar days it spans.  For example, with
  /// [maxDurationMinutes] = 2880, a slot created at 10pm on Jan 1 can
  /// extend through the full extent of Jan 3 (up to 2880 minutes).
  ///
  /// When null (the default), multi-day slots are not enabled and the
  /// slot is constrained to a single day (0–1440 minutes).
  final int? maxDurationMinutes;

  /// Returns the maximum duration (in minutes) a slot starting at
  /// [startMinuteOfDay] may have when [maxDurationMinutes] is set.
  ///
  /// Returns null when [maxDurationMinutes] is null (no cap).
  int? maxDurationForStartMinute(int startMinuteOfDay) {
    return maxDurationMinutes;
  }

  /// Minimum duration in minutes for any interactive slot.  Resize
  /// handles will never let the slot shrink below this value.
  /// Defaults to 15 minutes.
  final int minDurationMinutes;
}

// ──────────────────────────────────────────────────────────────────────────
// DaySnappingScrollPhysics — snaps flings to the nearest day-column
// boundary.  Unlike PageScrollPhysics (which snaps to viewport-width
// pages), this snaps to multiples of [pageSize], which is typically set
// to [dayWidth] for single-day snapping or [dayWidth * daysShowed] for
// bracket snapping.
// ──────────────────────────────────────────────────────────────────────────

class DaySnappingScrollPhysics extends ScrollPhysics {
  /// The width of one snap unit in logical pixels.
  final double pageSize;

  const DaySnappingScrollPhysics({required this.pageSize, super.parent});

  @override
  DaySnappingScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return DaySnappingScrollPhysics(pageSize: pageSize, parent: buildParent(ancestor));
  }

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    // Let the parent chain handle friction / bouncing.
    final Simulation? simulation = super.createBallisticSimulation(position, velocity);

    if (simulation == null) {
      return null;
    }

    // Find where the simulation would naturally end.
    final double naturalEnd = simulation.x(double.infinity);

    // Snap the natural end to the nearest page-size boundary.
    final double snappedEnd = (naturalEnd / pageSize).round() * pageSize;

    if (snappedEnd == naturalEnd) {
      // Already on a boundary.
      return simulation;
    }

    // Create a spring that drives from the current position to the
    // snapped boundary with the same initial velocity the fling had.
    return ScrollSpringSimulation(super.spring, position.pixels, snappedEnd, velocity, tolerance: tolerance);
  }
}
