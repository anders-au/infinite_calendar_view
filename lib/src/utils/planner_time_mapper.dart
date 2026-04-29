import 'dart:math';

/// Shared geometry mapper between minute-of-day and planner Y coordinates.
class PlannerTimeMapper {
  const PlannerTimeMapper({
    required this.heightPerMinute,
    this.hourCellGapPx = 0,
    this.paintGapAfterLastHour = false,
  })  : assert(heightPerMinute > 0),
        assert(hourCellGapPx >= 0);

  final double heightPerMinute;
  final double hourCellGapPx;
  final bool paintGapAfterLastHour;

  static const int minutesPerHour = 60;
  static const int hoursPerDay = 24;
  static const int minutesPerDay = minutesPerHour * hoursPerDay;

  double get hourHeight => heightPerMinute * minutesPerHour;

  double get hourBandHeight => hourHeight + hourCellGapPx;

  int get hourGapCount => paintGapAfterLastHour ? hoursPerDay : hoursPerDay - 1;

  double totalDayHeight() {
    return (hourHeight * hoursPerDay) + (hourCellGapPx * hourGapCount);
  }

  double minuteToY(double minute) {
    final clampedMinute = minute.clamp(0, minutesPerDay.toDouble());

    // Keep 24:00 at the bottom edge of the day.
    if (clampedMinute >= minutesPerDay) {
      return totalDayHeight();
    }

    final hourIndex = (clampedMinute ~/ minutesPerHour);
    final minuteInHour = clampedMinute - (hourIndex * minutesPerHour);
    return (hourIndex * hourBandHeight) + (minuteInHour * heightPerMinute);
  }

  /// Converts Y to minute-of-day using nearest-side behavior inside gaps.
  double yToMinute(double y) {
    final clampedY = y.clamp(0, totalDayHeight());

    if (clampedY >= totalDayHeight()) {
      return minutesPerDay.toDouble();
    }

    final bandIndex = (clampedY / hourBandHeight).floor();
    final localY = clampedY - (bandIndex * hourBandHeight);

    if (localY <= hourHeight) {
      final minuteInHour = localY / heightPerMinute;
      final minute = (bandIndex * minutesPerHour) + minuteInHour;
      return minute.clamp(0, minutesPerDay.toDouble());
    }

    // Gap zone: nearest-side snapping.
    final distanceToPreviousHour = localY - hourHeight;
    final distanceToNextHour = hourBandHeight - localY;

    if (distanceToPreviousHour <= distanceToNextHour || bandIndex >= hoursPerDay - 1) {
      final previousMinute = (bandIndex * minutesPerHour).toDouble() + (minutesPerHour - 0.001);
      return previousMinute.clamp(0, minutesPerDay.toDouble());
    }

    final nextMinute = ((bandIndex + 1) * minutesPerHour).toDouble();
    return min(nextMinute, minutesPerDay.toDouble());
  }
}
