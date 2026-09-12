import 'package:flutter/foundation.dart';

import 'utils/extension.dart';

/// Pure geometry for an item rendered across calendar day columns.
///
/// [endIsExclusive] controls whether a midnight end is the boundary after the
/// final occupied day. Source all-day event ranges may use an inclusive end;
/// interactive slots always use an exclusive end.
@immutable
class CalendarDaySpanGeometry {
  CalendarDaySpanGeometry({
    required this.start,
    required this.end,
    required this.dayWidth,
    required this.leadingPadding,
    required this.trailingGap,
    required this.endIsExclusive,
    this.usePartialDayBounds = false,
  }) : assert(dayWidth >= 0),
       assert(leadingPadding >= 0),
       assert(trailingGap >= 0),
       assert(end.isAfter(start));

  final DateTime start;
  final DateTime end;
  final double dayWidth;
  final double leadingPadding;
  final double trailingGap;
  final bool endIsExclusive;
  final bool usePartialDayBounds;

  int get dayCount {
    final lastOccupiedDay = _effectiveEnd.withoutTime;
    return lastOccupiedDay.difference(start.withoutTime).inDays + 1;
  }

  double get startInset =>
      usePartialDayBounds ? dayWidth * _fractionOfDay(start) : 0;

  double get endInset => usePartialDayBounds && !_isMidnight(end)
      ? dayWidth * (1 - _fractionOfDay(end))
      : 0;

  double naturalLeft(double contentLeft) =>
      contentLeft + leadingPadding + startInset;

  double get naturalWidth =>
      dayCount * dayWidth -
      leadingPadding * 2 -
      trailingGap -
      startInset -
      endInset;

  DateTime get _effectiveEnd {
    if (endIsExclusive && _isMidnight(end)) {
      return end.subtract(const Duration(microseconds: 1));
    }
    return end;
  }

  double _fractionOfDay(DateTime value) =>
      (value.hour * 60 * 60 * 1000 * 1000 +
          value.minute * 60 * 1000 * 1000 +
          value.second * 1000 * 1000 +
          value.millisecond * 1000 +
          value.microsecond) /
      const Duration(days: 1).inMicroseconds;

  bool _isMidnight(DateTime value) =>
      value.hour == 0 &&
      value.minute == 0 &&
      value.second == 0 &&
      value.millisecond == 0 &&
      value.microsecond == 0;
}
