import 'package:flutter/material.dart';

/// Programmatic controller for [EventsMonths].
///
/// Pass an instance to `EventsMonths(monthsViewController: ...)` to control
/// month/date navigation and zoom from outside the widget tree.
class MonthsViewController {
  MonthsAnimateDateAction? _animateToDateAction;
  MonthsJumpDateAction? _jumpToDateAction;
  MonthsAnimatePageAction? _animateToNextPageAction;
  MonthsAnimatePageAction? _animateToPreviousPageAction;
  MonthsJumpPageAction? _jumpToNextPageAction;
  MonthsJumpPageAction? _jumpToPreviousPageAction;
  MonthsAnimateZoomAction? _animateToZoomAction;
  MonthsJumpZoomAction? _jumpToZoomAction;
  MonthsZoomGetter? _zoomGetter;
  Object? _attachmentOwner;

  /// Whether this controller is currently attached to an [EventsMonths].
  bool get isAttached => _jumpToDateAction != null;

  /// Current month-view zoom value (`weekHeight`) when attached.
  double? get currentWeekHeight => _zoomGetter?.call();

  /// Animate month view to [date]'s month.
  Future<void> animateToDate(
    DateTime date, {
    Duration duration = const Duration(milliseconds: 250),
    Curve curve = Curves.easeInOut,
  }) {
    return _animateToDateAction?.call(date, duration, curve) ?? Future.value();
  }

  /// Jump month view to [date]'s month immediately.
  void jumpToDate(DateTime date) {
    _jumpToDateAction?.call(date);
  }

  /// Animate month view to next month page.
  Future<void> nextPage({
    Duration duration = const Duration(milliseconds: 250),
    Curve curve = Curves.easeInOut,
  }) {
    return _animateToNextPageAction?.call(duration, curve) ?? Future.value();
  }

  /// Animate month view to previous month page.
  Future<void> previousPage({
    Duration duration = const Duration(milliseconds: 250),
    Curve curve = Curves.easeInOut,
  }) {
    return _animateToPreviousPageAction?.call(duration, curve) ?? Future.value();
  }

  /// Jump month view to next month page immediately.
  void jumpToNextPage() {
    _jumpToNextPageAction?.call();
  }

  /// Jump month view to previous month page immediately.
  void jumpToPreviousPage() {
    _jumpToPreviousPageAction?.call();
  }

  /// Animate month zoom (`weekHeight`) to [weekHeight].
  Future<void> animateToZoom(
    double weekHeight, {
    Duration duration = const Duration(milliseconds: 250),
    Curve curve = Curves.easeInOut,
  }) {
    return _animateToZoomAction?.call(weekHeight, duration, curve) ?? Future.value();
  }

  /// Set month zoom (`weekHeight`) immediately.
  void setZoom(double weekHeight) {
    _jumpToZoomAction?.call(weekHeight);
  }

  void attach({
    Object? owner,
    required MonthsAnimateDateAction animateToDate,
    required MonthsJumpDateAction jumpToDate,
    required MonthsAnimatePageAction animateToNextPage,
    required MonthsAnimatePageAction animateToPreviousPage,
    required MonthsJumpPageAction jumpToNextPage,
    required MonthsJumpPageAction jumpToPreviousPage,
    required MonthsAnimateZoomAction animateToZoom,
    required MonthsJumpZoomAction jumpToZoom,
    required MonthsZoomGetter zoomGetter,
  }) {
    _attachmentOwner = owner;
    _animateToDateAction = animateToDate;
    _jumpToDateAction = jumpToDate;
    _animateToNextPageAction = animateToNextPage;
    _animateToPreviousPageAction = animateToPreviousPage;
    _jumpToNextPageAction = jumpToNextPage;
    _jumpToPreviousPageAction = jumpToPreviousPage;
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
    _animateToZoomAction = null;
    _jumpToZoomAction = null;
    _zoomGetter = null;
    _attachmentOwner = null;
  }
}

typedef MonthsAnimateDateAction = Future<void> Function(DateTime date, Duration duration, Curve curve);
typedef MonthsJumpDateAction = void Function(DateTime date);
typedef MonthsAnimatePageAction = Future<void> Function(Duration duration, Curve curve);
typedef MonthsJumpPageAction = void Function();
typedef MonthsAnimateZoomAction = Future<void> Function(double weekHeight, Duration duration, Curve curve);
typedef MonthsJumpZoomAction = void Function(double weekHeight);
typedef MonthsZoomGetter = double Function();
