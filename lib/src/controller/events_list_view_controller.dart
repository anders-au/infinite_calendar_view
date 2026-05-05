import 'package:flutter/material.dart';

/// Programmatic controller for [EventsList].
///
/// Pass an instance to `EventsList(listViewController: ...)` to control
/// date/day navigation from outside the widget tree.
class EventsListViewController {
  EventsListAnimateDateAction? _animateToDateAction;
  EventsListJumpDateAction? _jumpToDateAction;
  EventsListAnimatePageAction? _animateToNextPageAction;
  EventsListAnimatePageAction? _animateToPreviousPageAction;
  EventsListJumpPageAction? _jumpToNextPageAction;
  EventsListJumpPageAction? _jumpToPreviousPageAction;
  EventsListDateVisibleGetter? _isDateVisibleGetter;
  EventsListTodayVisibleGetter? _isTodayVisibleGetter;
  Object? _attachmentOwner;

  /// Whether this controller is currently attached to an [EventsList].
  bool get isAttached => _jumpToDateAction != null;

  /// Animate list to make [date] visible.
  Future<void> animateToDate(
    DateTime date, {
    Duration duration = const Duration(milliseconds: 250),
    Curve curve = Curves.easeInOut,
  }) {
    return _animateToDateAction?.call(date, duration, curve) ?? Future.value();
  }

  /// Jump list to make [date] visible immediately.
  void jumpToDate(DateTime date) {
    _jumpToDateAction?.call(date);
  }

  /// Animate list to next day page.
  Future<void> nextPage({
    Duration duration = const Duration(milliseconds: 250),
    Curve curve = Curves.easeInOut,
  }) {
    return _animateToNextPageAction?.call(duration, curve) ?? Future.value();
  }

  /// Animate list to previous day page.
  Future<void> previousPage({
    Duration duration = const Duration(milliseconds: 250),
    Curve curve = Curves.easeInOut,
  }) {
    return _animateToPreviousPageAction?.call(duration, curve) ??
        Future.value();
  }

  /// Jump list to next day page immediately.
  void jumpToNextPage() {
    _jumpToNextPageAction?.call();
  }

  /// Jump list to previous day page immediately.
  void jumpToPreviousPage() {
    _jumpToPreviousPageAction?.call();
  }

  /// Whether [date] is currently visible at the top of the list viewport.
  bool isDateVisible(DateTime date) {
    return _isDateVisibleGetter?.call(date) ?? false;
  }

  /// Whether today is currently visible at the top of the list viewport.
  bool isTodayVisible() {
    return _isTodayVisibleGetter?.call() ?? false;
  }

  void attach({
    Object? owner,
    required EventsListAnimateDateAction animateToDate,
    required EventsListJumpDateAction jumpToDate,
    required EventsListAnimatePageAction animateToNextPage,
    required EventsListAnimatePageAction animateToPreviousPage,
    required EventsListJumpPageAction jumpToNextPage,
    required EventsListJumpPageAction jumpToPreviousPage,
    required EventsListDateVisibleGetter isDateVisible,
    required EventsListTodayVisibleGetter isTodayVisible,
  }) {
    _attachmentOwner = owner;
    _animateToDateAction = animateToDate;
    _jumpToDateAction = jumpToDate;
    _animateToNextPageAction = animateToNextPage;
    _animateToPreviousPageAction = animateToPreviousPage;
    _jumpToNextPageAction = jumpToNextPage;
    _jumpToPreviousPageAction = jumpToPreviousPage;
    _isDateVisibleGetter = isDateVisible;
    _isTodayVisibleGetter = isTodayVisible;
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
    _isDateVisibleGetter = null;
    _isTodayVisibleGetter = null;
    _attachmentOwner = null;
  }
}

typedef EventsListAnimateDateAction = Future<void> Function(
    DateTime date, Duration duration, Curve curve);
typedef EventsListJumpDateAction = void Function(DateTime date);
typedef EventsListAnimatePageAction = Future<void> Function(
    Duration duration, Curve curve);
typedef EventsListJumpPageAction = void Function();
typedef EventsListDateVisibleGetter = bool Function(DateTime date);
typedef EventsListTodayVisibleGetter = bool Function();
