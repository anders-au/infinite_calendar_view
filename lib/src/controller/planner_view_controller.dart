import 'package:flutter/material.dart';

/// Programmatic controller for [EventsPlanner].
///
/// Pass an instance to `EventsPlanner(plannerViewController: ...)` to control
/// date, page, time, and zoom from outside the widget tree.
class PlannerViewController {
  PlannerAnimateDateAction? _animateToDateAction;
  PlannerJumpDateAction? _jumpToDateAction;
  PlannerAnimatePageAction? _animateToNextPageAction;
  PlannerAnimatePageAction? _animateToPreviousPageAction;
  PlannerJumpPageAction? _jumpToNextPageAction;
  PlannerJumpPageAction? _jumpToPreviousPageAction;
  PlannerAnimateTimeAction? _animateToTimeAction;
  PlannerJumpTimeAction? _jumpToTimeAction;
  PlannerAnimateZoomAction? _animateToZoomAction;
  PlannerJumpZoomAction? _jumpToZoomAction;
  PlannerZoomGetter? _zoomGetter;
  Object? _attachmentOwner;
  double _verticalViewportAnchor = 0.2;

  /// Whether this controller is currently attached to an [EventsPlanner].
  bool get isAttached => _jumpToDateAction != null;

  /// The current planner zoom value (`heightPerMinute`) when attached.
  double? get currentHeightPerMinute => _zoomGetter?.call();

  /// Vertical alignment anchor used by time-based navigation.
  ///
  /// `0` aligns target to the top edge, `0.5` to the middle, and `1` to the
  /// bottom edge. Defaults to `0.2` (20% from top).
  double get verticalViewportAnchor => _verticalViewportAnchor;

  set verticalViewportAnchor(double value) {
    _verticalViewportAnchor = value.clamp(0.0, 1.0);
  }

  /// Animate planner to make [date] visible.
  Future<void> animateToDate(
    DateTime date, {
    Duration duration = const Duration(milliseconds: 250),
    Curve curve = Curves.easeInOut,
  }) {
    return _animateToDateAction?.call(date, duration, curve) ?? Future.value();
  }

  /// Jump planner to make [date] visible immediately.
  void jumpToDate(DateTime date) {
    _jumpToDateAction?.call(date);
  }

  /// Animate to the next planner page (`daysShowed` days).
  Future<void> nextPage({
    Duration duration = const Duration(milliseconds: 250),
    Curve curve = Curves.easeInOut,
  }) {
    return _animateToNextPageAction?.call(duration, curve) ?? Future.value();
  }

  /// Animate to the previous planner page (`daysShowed` days).
  Future<void> previousPage({
    Duration duration = const Duration(milliseconds: 250),
    Curve curve = Curves.easeInOut,
  }) {
    return _animateToPreviousPageAction?.call(duration, curve) ?? Future.value();
  }

  /// Jump to the next planner page (`daysShowed` days).
  void jumpToNextPage() {
    _jumpToNextPageAction?.call();
  }

  /// Jump to the previous planner page (`daysShowed` days).
  void jumpToPreviousPage() {
    _jumpToPreviousPageAction?.call();
  }

  /// Animate vertical planner scroll to [time].
  Future<void> animateToTime(
    TimeOfDay time, {
    Duration duration = const Duration(milliseconds: 250),
    Curve curve = Curves.easeInOut,
  }) {
    return _animateToTimeAction?.call(time, duration, curve) ?? Future.value();
  }

  /// Jump vertical planner scroll to [time] immediately.
  void jumpToTime(TimeOfDay time) {
    _jumpToTimeAction?.call(time);
  }

  /// Animate planner to current date and time.
  Future<void> animateToNow({
    Duration duration = const Duration(milliseconds: 250),
    Curve curve = Curves.easeInOut,
  }) async {
    if (!isAttached) {
      return;
    }
    final now = DateTime.now();
    final nowTime = TimeOfDay(hour: now.hour, minute: now.minute);
    await animateToDate(now, duration: duration, curve: curve);
    await WidgetsBinding.instance.endOfFrame;
    await animateToTime(nowTime, duration: duration, curve: curve);
    // Ensure final alignment even if an in-flight rebuild interrupted animation.
    jumpToTime(nowTime);
  }

  /// Jump planner to current date and time immediately.
  void jumpToNow() {
    final now = DateTime.now();
    jumpToDate(now);
    jumpToTime(TimeOfDay(hour: now.hour, minute: now.minute));
  }

  /// Animate planner zoom to [heightPerMinute].
  Future<void> animateToZoom(
    double heightPerMinute, {
    Duration duration = const Duration(milliseconds: 250),
    Curve curve = Curves.easeInOut,
  }) {
    return _animateToZoomAction?.call(heightPerMinute, duration, curve) ?? Future.value();
  }

  /// Set planner zoom immediately to [heightPerMinute].
  void setZoom(double heightPerMinute) {
    _jumpToZoomAction?.call(heightPerMinute);
  }

  void attach({
    Object? owner,
    required PlannerAnimateDateAction animateToDate,
    required PlannerJumpDateAction jumpToDate,
    required PlannerAnimatePageAction animateToNextPage,
    required PlannerAnimatePageAction animateToPreviousPage,
    required PlannerJumpPageAction jumpToNextPage,
    required PlannerJumpPageAction jumpToPreviousPage,
    required PlannerAnimateTimeAction animateToTime,
    required PlannerJumpTimeAction jumpToTime,
    required PlannerAnimateZoomAction animateToZoom,
    required PlannerJumpZoomAction jumpToZoom,
    required PlannerZoomGetter zoomGetter,
  }) {
    _attachmentOwner = owner;
    _animateToDateAction = animateToDate;
    _jumpToDateAction = jumpToDate;
    _animateToNextPageAction = animateToNextPage;
    _animateToPreviousPageAction = animateToPreviousPage;
    _jumpToNextPageAction = jumpToNextPage;
    _jumpToPreviousPageAction = jumpToPreviousPage;
    _animateToTimeAction = animateToTime;
    _jumpToTimeAction = jumpToTime;
    _animateToZoomAction = animateToZoom;
    _jumpToZoomAction = jumpToZoom;
    _zoomGetter = zoomGetter;
  }

  void detach({Object? owner}) {
    if (owner != null && !identical(owner, _attachmentOwner)) {
      return;
    }
    _animateToDateAction = null;
    _jumpToDateAction = null;
    _animateToNextPageAction = null;
    _animateToPreviousPageAction = null;
    _jumpToNextPageAction = null;
    _jumpToPreviousPageAction = null;
    _animateToTimeAction = null;
    _jumpToTimeAction = null;
    _animateToZoomAction = null;
    _jumpToZoomAction = null;
    _zoomGetter = null;
    _attachmentOwner = null;
  }
}

typedef PlannerAnimateDateAction = Future<void> Function(DateTime date, Duration duration, Curve curve);
typedef PlannerJumpDateAction = void Function(DateTime date);
typedef PlannerAnimatePageAction = Future<void> Function(Duration duration, Curve curve);
typedef PlannerJumpPageAction = void Function();
typedef PlannerAnimateTimeAction = Future<void> Function(TimeOfDay time, Duration duration, Curve curve);
typedef PlannerJumpTimeAction = void Function(TimeOfDay time);
typedef PlannerAnimateZoomAction = Future<void> Function(double heightPerMinute, Duration duration, Curve curve);
typedef PlannerJumpZoomAction = void Function(double heightPerMinute);
typedef PlannerZoomGetter = double Function();
