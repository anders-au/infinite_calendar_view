import 'dart:ui';

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
    this.hourCellGapPx = 0,
    this.paintGapAfterLastHour = false,
    this.daySeparationWidth = 3.0,
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
    this.automaticAdjustHorizontalScrollToDay = true,
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

  /// Visual spacing between hour cells in planner.
  final double hourCellGapPx;

  /// Whether to paint an additional gap after the last hour (23:00-24:00).
  final bool paintGapAfterLastHour;

  /// separation between two day
  final double daySeparationWidth;

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
  final bool automaticAdjustHorizontalScrollToDay;

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
  final Object _plannerViewControllerOwner = Object();

  PlannerTimeMapper get plannerTimeMapper => PlannerTimeMapper(
        heightPerMinute: heightPerMinute,
        hourCellGapPx: widget.hourCellGapPx,
        paintGapAfterLastHour: widget.paintGapAfterLastHour,
      );

  @override
  void initState() {
    super.initState();
    heightPerMinute = widget.heightPerMinute;
    _controller = widget.controller;
    initialDate = widget.initialDate?.withoutTime ?? widget.controller.focusedDay;
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // index calculation and first day showed
      initDayChangingListener();

      // Automatic adjust horizontal scroll to nearest day
      if (widget.automaticAdjustHorizontalScrollToDay) {
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
          if (_plannerPointerDownCount < 2) {
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

    super.dispose();
  }

  /// listen mainHorizontalController and call onFirstDayChange when day change
  void initDayChangingListener() {
    var halfDayWidth = (dayWidth / 2);
    var scroll = mainHorizontalController;
    _dayChangingListener = () {
      if (_listenHorizontalScrollDayChange) {
        var halfDay = scroll.offset >= 0 ? halfDayWidth : -halfDayWidth;
        var index = ((scroll.offset + halfDay) / dayWidth).toInt();
        // only when index has changed
        if (index != currentIndex) {
          currentIndex = index;
          var currentDay =
              widget.textDirection == TextDirection.ltr ? getDayFromIndex(currentIndex) : getDayFromIndex(currentIndex + widget.daysShowed - 1);
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
  /// call onAutomaticAdjustHorizontalScroll when end adjust
  VoidCallback getAutomaticScrollAdjustListener() {
    return () {
      // when scroll stopped
      var scroll = mainHorizontalController;
      var stopScroll = !scroll.position.isScrollingNotifier.value;
      if (_listenHorizontalScrollDayChange && stopScroll) {
        // Round to nearest day
        var nearestDayOffset = dayWidth * (scroll.offset / dayWidth).round();
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

  bool _handleKeyEvent(KeyEvent event) {
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;

    //  listen ctrl or cmd key to zoom in web/desktop
    if (widget.pinchToZoomParam.pinchToZoom) {
      final isModifierPressed = pressed.contains(LogicalKeyboardKey.controlLeft) ||
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
    var daySeparationWidthPadding = widget.daySeparationWidth / 2;
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
          if (widget.fullDayParam.fullDayEventsBarVisibility) getHorizontalFullDayEventsWidget(daySeparationWidthPadding, todayColor),
        ];

        return Column(
          children: [
            if (headerWidgets.isNotEmpty)
              _buildHeaderHorizontalDragArea(
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: headerWidgets,
                ),
              ),

            // days content
            Expanded(child: getPlannerAndTimesWidget(plannerHeight, currentHourIndicatorColor, todayColor, daySeparationWidthPadding)),
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

  Widget getPlannerAndTimesWidget(double plannerHeight, Color currentHourIndicatorColor, Color todayColor, double daySeparationWidthPadding) {
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
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 0, top: 0),
                      child: SizedBox(
                        height: plannerHeight,
                        child: Row(
                          textDirection: widget.textDirection,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // left Timeline
                            getVerticalTimeIndicatorWidget(currentHourIndicatorColor),

                            // day planning infinite list
                            Expanded(child: getPlannerWidget(todayColor, daySeparationWidthPadding, plannerHeight, currentHourIndicatorColor)),
                          ],
                        ),
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

  Widget getPlannerWidget(Color todayColor, double daySeparationWidthPadding, double plannerHeight, Color currentHourIndicatorColor) {
    var physics = _plannerPointerDownCount > 1 ? const NeverScrollableScrollPhysics() : widget.horizontalScrollPhysics;

    return ScrollConfiguration(
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

          // notify day will be build
          Future(() => widget.dayParam.onDayBuild?.call(day));

          return InfiniteListItem(
            contentBuilder: (context) {
              return DayWidget(
                controller: _controller,
                textDirection: widget.textDirection,
                day: day,
                todayColor: todayColor,
                daySeparationWidthPadding: daySeparationWidthPadding,
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
              );
            },
          );
        },
      ),
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

  HorizontalFullDayEventsWidget getHorizontalFullDayEventsWidget(double daySeparationWidthPadding, Color todayColor) {
    return HorizontalFullDayEventsWidget(
      controller: _controller,
      textDirection: widget.textDirection,
      fullDayParam: widget.fullDayParam,
      columnsParam: widget.columnsParam,
      daySeparationWidthPadding: daySeparationWidthPadding,
      dayHorizontalController: headersHorizontalController,
      maxPreviousDays: widget.maxPreviousDays,
      maxNextDays: widget.maxNextDays,
      initialDate: initialDate,
      dayWidth: dayWidth,
      todayColor: todayColor,
      timesIndicatorsWidth: widget.timesIndicatorsParam.timesIndicatorsWidth,
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

  double _mapOffsetForNewHeightPerMinute({
    required double oldOffset,
    required double oldHeightPerMinute,
    required double newHeightPerMinute,
  }) {
    final oldMapper = PlannerTimeMapper(
      heightPerMinute: oldHeightPerMinute,
      hourCellGapPx: widget.hourCellGapPx,
      paintGapAfterLastHour: widget.paintGapAfterLastHour,
    );
    final newMapper = PlannerTimeMapper(
      heightPerMinute: newHeightPerMinute,
      hourCellGapPx: widget.hourCellGapPx,
      paintGapAfterLastHour: widget.paintGapAfterLastHour,
    );
    final minute = oldMapper.yToMinute(oldOffset);
    return newMapper.minuteToY(minute);
  }

  void _onScaleEnd(ScaleEndDetails details) {
    widget.controller.notifyListeners();
    widget.pinchToZoomParam.onZoomChange?.call(heightPerMinute);
    if (widget.automaticAdjustHorizontalScrollToDay && automaticScrollAdjustListener != null) {
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

  DateTime _currentVisibleFirstDay() {
    if (!_hasResolvedVisibleFirstDay) {
      return initialDate;
    }
    return topLeftCellValueNotifier.value.withoutTime;
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
    final firstVisibleDay = _currentVisibleFirstDay();
    final delta = normalized.getDayDifference(firstVisibleDay);
    final bracketIndex = _floorDiv(delta, widget.daysShowed);
    return firstVisibleDay.addCalendarDays(bracketIndex * widget.daysShowed);
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
    if (_isDayAlreadyVisible(date)) {
      widget.controller.updateFocusedDay(date.withoutTime);
      return;
    }
    _listenHorizontalScrollDayChange = false;
    try {
      final targetDay = _getBracketStartDayForTarget(date);
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
    if (_isDayAlreadyVisible(date)) {
      widget.controller.updateFocusedDay(date.withoutTime);
      return;
    }
    final targetDay = _getBracketStartDayForTarget(date);
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
    return newHeightPerMinute.clamp(
      widget.pinchToZoomParam.pinchToZoomMinHeightPerMinute,
      widget.pinchToZoomParam.pinchToZoomMaxHeightPerMinute,
    );
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
    final double mappedOffset = _mapOffsetForNewHeightPerMinute(
      oldOffset: oldOffset,
      oldHeightPerMinute: oldHeight,
      newHeightPerMinute: clamped,
    );

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
    this.onSlotMinutesRound = 15,
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
    this.slotSelectionContentBuilder,
    this.slotSelectionBuilder,
    this.onSlotSelectionChange,
    this.onSlotSelectionTap,
    this.onSlotSelectionLongPress,
    this.enableSlotSelectionResize = true,
    this.slotSelectionTopHandleBuilder,
    this.slotSelectionBottomHandleBuilder,
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

  /// interactive slot selection content in default InteractiveSlot
  final Widget Function(SlotSelection slot)? slotSelectionContentBuilder;

  /// interactive slot selection builder
  final Widget Function(
    SlotSelection slot,
    double dayWidth,
    DayParam dayParam,
    ColumnsParam columnsParam,
    double heightPerMinute,
    void Function(SlotSelection? updatedSlot) onChanged,
  )? slotSelectionBuilder;

  /// event when tap on interactive slot
  final void Function(SlotSelection? slot)? onSlotSelectionChange;

  /// event when tap on interactive slot
  final void Function(SlotSelection slot)? onSlotSelectionTap;

  /// event when long press on interactive slot
  final void Function(SlotSelection slot)? onSlotSelectionLongPress;

  /// enable interactive slot selection top and bottom handle for resize
  final bool enableSlotSelectionResize;

  /// interactive slot selection top handle builder (for resize)
  final Widget Function()? slotSelectionTopHandleBuilder;

  /// interactive slot selection bottom handle builder (for resize)
  final Widget Function()? slotSelectionBottomHandleBuilder;
}

class SlotSelection {
  // current column
  final int columnIndex;

  // initial interactive slot start date when slot have been created
  final DateTime initialStartDateTime;

  // current interactive slot start date
  final DateTime startDateTime;

  // current interactive slot duration
  final int durationInMinutes;

  SlotSelection(this.columnIndex, this.initialStartDateTime, this.startDateTime, this.durationInMinutes);
}
