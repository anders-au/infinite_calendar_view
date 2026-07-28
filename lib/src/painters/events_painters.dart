import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../infinite_calendar_view.dart';
import '../utils/planner_time_mapper.dart';

enum SlotTimeIndicatorBoundary { start, end }

class SlotTimeIndicator {
  const SlotTimeIndicator({required this.minute, required this.boundary});

  final int minute;
  final SlotTimeIndicatorBoundary boundary;
}

class SlotTimeIndicators {
  const SlotTimeIndicators({
    required this.indicators,
    required this.color,
    required this.backgroundColor,
    required this.use24HourFormat,
    this.textStyle,
  });

  final List<SlotTimeIndicator> indicators;
  List<int> get minutes =>
      indicators.map((indicator) => indicator.minute).toList();
  final Color color;
  final Color backgroundColor;
  final bool use24HourFormat;
  final TextStyle? textStyle;
}

/// Optional contract that lets a custom time-column painter render interactive
/// slot indicators using the same override path as its current-time indicator.
abstract interface class SlotAwareTimeIndicatorPainter {
  CustomPainter withSlotTimeIndicators(SlotTimeIndicators indicators);
}

class LinesPainter extends CustomPainter {
  const LinesPainter({
    required this.heightPerMinute,
    this.plannerTimeMapper,
    required this.isToday,
    required this.lineColor,
    this.hourStrokeWidth = 0.5,
    this.halfStrokeWidth = 0.2,
    this.quarterStrokeWidth = 0.1,
    this.verticalStrokeWidth = 0.5,
    this.drawHalfHour = true,
    this.drawQuarterHour = true,
    this.drawVerticalLeftLine = false,
    this.drawVerticalRightLine = false,
    this.slotPainter,
  });

  final double heightPerMinute;
  final PlannerTimeMapper? plannerTimeMapper;
  final bool isToday;
  final Color lineColor;
  final double hourStrokeWidth;
  final double halfStrokeWidth;
  final double quarterStrokeWidth;
  final double verticalStrokeWidth;
  final bool drawHalfHour;
  final bool drawQuarterHour;
  final bool drawVerticalLeftLine;
  final bool drawVerticalRightLine;
  final TextPainter? slotPainter;

  PlannerTimeMapper get _mapper =>
      plannerTimeMapper ?? PlannerTimeMapper(heightPerMinute: heightPerMinute);

  @override
  void paint(Canvas canvas, Size size) {
    final mapper = _mapper;

    final hourPaint = Paint()
      ..color = lineColor
      ..strokeWidth = hourStrokeWidth;

    final halfHourPaint = Paint()
      ..color = lineColor
      ..strokeWidth = halfStrokeWidth;

    final quarterHourPaint = Paint()
      ..color = lineColor
      ..strokeWidth = quarterStrokeWidth;

    final verticalPaint = Paint()
      ..color = lineColor
      ..strokeWidth = verticalStrokeWidth;

    for (var i = 0; i < 24; i++) {
      final startMinute = i * 60;
      final endMinute = (i + 1) * 60;
      final hourY = mapper.minuteToY(startMinute.toDouble());
      canvas.drawLine(Offset(0, hourY), Offset(size.width, hourY), hourPaint);

      if (slotPainter != null) {
        slotPainter?.layout();
        final dx = (size.width - slotPainter!.width) / 2;
        final cellHeight = mapper.minuteToY(endMinute.toDouble()) - hourY;
        final dy = hourY + (cellHeight - slotPainter!.height) / 2;
        slotPainter?.paint(canvas, Offset(dx, dy));
      }

      if (drawHalfHour) {
        final halfHourY = mapper.minuteToY((startMinute + 30).toDouble());
        canvas.drawLine(
          Offset(0, halfHourY),
          Offset(size.width, halfHourY),
          halfHourPaint,
        );
      }

      if (drawQuarterHour && heightPerMinute > 2) {
        final quarterHourY15 = mapper.minuteToY((startMinute + 15).toDouble());
        final quarterHourY45 = mapper.minuteToY((startMinute + 45).toDouble());
        canvas.drawLine(
          Offset(0, quarterHourY15),
          Offset(size.width, quarterHourY15),
          quarterHourPaint,
        );
        canvas.drawLine(
          Offset(0, quarterHourY45),
          Offset(size.width, quarterHourY45),
          quarterHourPaint,
        );
      }
    }
    // draw 24:00
    final dayEndY = mapper.minuteToY((24 * 60).toDouble());
    canvas.drawLine(Offset(0, dayEndY), Offset(size.width, dayEndY), hourPaint);

    if (drawVerticalLeftLine) {
      canvas.drawLine(Offset(0, 0), Offset(0, size.height), verticalPaint);
    }
    if (drawVerticalRightLine) {
      canvas.drawLine(
        Offset(size.width, 0),
        Offset(size.width, size.height),
        verticalPaint,
      );
    }
  }

  @override
  bool shouldRepaint(LinesPainter oldDelegate) => false;
}

class TimeIndicatorPainter extends CustomPainter {
  const TimeIndicatorPainter(
    this.heightPerMinute,
    this.isToday,
    this.color, {
    this.plannerTimeMapper,
  });

  final double heightPerMinute;
  final bool isToday;
  final Color color;
  final PlannerTimeMapper? plannerTimeMapper;

  PlannerTimeMapper get _mapper =>
      plannerTimeMapper ?? PlannerTimeMapper(heightPerMinute: heightPerMinute);

  @override
  void paint(Canvas canvas, Size size) {
    var currentTime = DateTime.now();

    // draw current time line
    if (isToday) {
      final currentTimePaint = Paint()
        ..color = color
        ..strokeWidth = 0.75;
      var currentTimeLineY = _mapper.minuteToY(
        (currentTime.hour * 60 + currentTime.minute).toDouble(),
      );
      canvas.drawLine(
        Offset(0, currentTimeLineY),
        Offset(size.width, currentTimeLineY),
        currentTimePaint,
      );
      canvas.drawCircle(Offset(1, currentTimeLineY), 3, currentTimePaint);
    }
  }

  @override
  bool shouldRepaint(TimeIndicatorPainter oldDelegate) => true;
}

class HoursPainter extends CustomPainter {
  const HoursPainter({
    required this.heightPerMinute,
    this.plannerTimeMapper,
    this.textDirection = TextDirection.ltr,
    this.showCurrentHour = true,
    this.hourColor = Colors.black12,
    this.halfHourColor = Colors.black12,
    this.quarterHourColor = Colors.black12,
    this.currentHourIndicatorColor = Colors.black12,
    this.slotIndicatorMinutes = const [],
    this.slotIndicatorColor = Colors.black12,
    this.slotIndicatorTextStyle,
    this.slotIndicatorBackgroundColor = Colors.transparent,
    this.slotUse24HourFormat = true,
    this.showRegularHours = true,
    this.floatingIndicatorTopInset = 0,
    this.halfHourMinHeightPerMinute = 1.3,
    this.quarterHourMinHeightPerMinute = 2,
    this.textPainterBuilder,
  });

  final double heightPerMinute;
  final PlannerTimeMapper? plannerTimeMapper;
  final TextDirection textDirection;
  final bool showCurrentHour;
  final Color hourColor;
  final Color halfHourColor;
  final Color quarterHourColor;
  final Color currentHourIndicatorColor;
  final List<int> slotIndicatorMinutes;
  final Color slotIndicatorColor;
  final TextStyle? slotIndicatorTextStyle;
  final Color slotIndicatorBackgroundColor;
  final bool slotUse24HourFormat;
  final bool showRegularHours;
  final double floatingIndicatorTopInset;
  final double halfHourMinHeightPerMinute;
  final double quarterHourMinHeightPerMinute;
  final TextPainter Function(TimeOfDay time, Color defaultColor)?
  textPainterBuilder;

  PlannerTimeMapper get _mapper =>
      plannerTimeMapper ?? PlannerTimeMapper(heightPerMinute: heightPerMinute);

  @override
  void paint(Canvas canvas, Size size) {
    final mapper = _mapper;

    // draw currentHour
    var currentTime = TimeOfDay.now();
    final slotYs = slotIndicatorMinutes
        .map(
          (minute) =>
              floatingIndicatorTopInset + mapper.minuteToY(minute.toDouble()),
        )
        .toList();
    final currentY =
        floatingIndicatorTopInset +
        mapper.minuteToY(currentTime.totalMinutes.toDouble());
    if (showCurrentHour && !slotYs.any((y) => (y - currentY).abs() <= 10)) {
      drawFloatingHour(
        canvas,
        size,
        currentTime,
        currentY,
        currentHourIndicatorColor,
      );
    }

    for (var index = 0; index < slotIndicatorMinutes.length; index++) {
      drawSlotHour(canvas, size, slotIndicatorMinutes[index], slotYs[index]);
    }

    if (showRegularHours) {
      // draw normal hour
      for (var i = 0; i <= 23; i++) {
        // hour
        final hourY = mapper.minuteToY((i * 60).toDouble()) + 4;
        if (!isHiddenByIndicator(currentTime, hourY, slotYs)) {
          drawHour(
            canvas,
            size,
            TimeOfDay(hour: i, minute: 0),
            hourY,
            hourColor,
          );
        }

        // half
        final halfY = mapper.minuteToY(((i * 60) + 30).toDouble()) + 4;
        if (heightPerMinute > halfHourMinHeightPerMinute &&
            !isHiddenByIndicator(currentTime, halfY, slotYs)) {
          drawHour(
            canvas,
            size,
            TimeOfDay(hour: i, minute: 30),
            halfY,
            halfHourColor,
          );
        }

        // quart15
        final quarterY15 = mapper.minuteToY(((i * 60) + 15).toDouble()) + 4;
        if (heightPerMinute > quarterHourMinHeightPerMinute &&
            !isHiddenByIndicator(currentTime, quarterY15, slotYs)) {
          drawHour(
            canvas,
            size,
            TimeOfDay(hour: i, minute: 15),
            quarterY15,
            quarterHourColor,
          );
        }

        // quart45
        final quarterY45 = mapper.minuteToY(((i * 60) + 45).toDouble()) + 4;
        if (heightPerMinute > quarterHourMinHeightPerMinute &&
            !isHiddenByIndicator(currentTime, quarterY45, slotYs)) {
          drawHour(
            canvas,
            size,
            TimeOfDay(hour: i, minute: 45),
            quarterY45,
            quarterHourColor,
          );
        }
      }

      // 24:00 hour
      final hourY = mapper.minuteToY((24 * 60).toDouble()) + 4;
      if (!isHiddenByIndicator(currentTime, hourY, slotYs)) {
        drawHour(
          canvas,
          size,
          TimeOfDay(hour: 24, minute: 0),
          hourY,
          hourColor,
        );
      }
    }
  }

  bool isHiddenByIndicator(
    TimeOfDay currentTime,
    double y,
    List<double> slotYs,
  ) {
    final currentY =
        floatingIndicatorTopInset +
        _mapper.minuteToY(currentTime.totalMinutes.toDouble());
    return (showCurrentHour && (currentY - y).abs() <= 10) ||
        slotYs.any((slotY) => (slotY - y).abs() <= 10);
  }

  void drawHour(
    Canvas canvas,
    Size size,
    TimeOfDay time,
    double y,
    Color color, {
    TextStyle? textStyle,
  }) {
    var textPainter =
        textPainterBuilder?.call(time, color) ??
        getDefaultTextPainter(time, color, textStyle: textStyle);
    textPainter.layout(minWidth: size.width, maxWidth: size.width);
    textPainter.paint(canvas, Offset(0, y));
  }

  void drawFloatingHour(
    Canvas canvas,
    Size size,
    TimeOfDay time,
    double centerY,
    Color color,
  ) {
    final painter =
        textPainterBuilder?.call(time, color) ??
        getDefaultTextPainter(time, color);
    painter.layout(minWidth: size.width, maxWidth: size.width);
    painter.paint(canvas, Offset(0, centerY - painter.height / 2));
  }

  void drawSlotHour(Canvas canvas, Size size, int minute, double y) {
    final hour = minute ~/ 60;
    final minuteOfHour = minute % 60;
    final paddedMinute = minuteOfHour.toString().padLeft(2, '0');
    final text = slotUse24HourFormat
        ? '${hour.toString().padLeft(2, '0')}:$paddedMinute'
        : '${hour == 0 || hour == 24 ? 12 : (hour > 12 ? hour - 12 : hour)}'
              ':$paddedMinute ${hour >= 12 && hour < 24 ? 'pm' : 'am'}';
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: slotIndicatorColor,
          fontSize: 12,
        ).merge(slotIndicatorTextStyle),
      ),
      textDirection: textDirection,
      textAlign: textDirection == TextDirection.ltr
          ? TextAlign.right
          : TextAlign.left,
    )..layout(minWidth: size.width, maxWidth: size.width);
    final top = y - painter.height / 2;
    if (slotIndicatorBackgroundColor.a > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, top, size.width, painter.height),
        Paint()..color = slotIndicatorBackgroundColor,
      );
    }
    painter.paint(canvas, Offset(0, top));
  }

  TextPainter getDefaultTextPainter(
    TimeOfDay time,
    Color color, {
    TextStyle? textStyle,
  }) {
    return TextPainter(
      text: TextSpan(
        text: "${time.hour.toTimeText()}:${time.minute.toTimeText()}",
        style: TextStyle(color: color, fontSize: 12).merge(textStyle),
      ),
      textDirection: textDirection,
      textAlign: textDirection == TextDirection.ltr
          ? TextAlign.right
          : TextAlign.left,
    );
  }

  @override
  bool shouldRepaint(HoursPainter oldDelegate) =>
      oldDelegate.heightPerMinute != heightPerMinute ||
      oldDelegate.plannerTimeMapper != plannerTimeMapper ||
      oldDelegate.textDirection != textDirection ||
      oldDelegate.showCurrentHour != showCurrentHour ||
      oldDelegate.currentHourIndicatorColor != currentHourIndicatorColor ||
      !listEquals(oldDelegate.slotIndicatorMinutes, slotIndicatorMinutes) ||
      oldDelegate.slotIndicatorColor != slotIndicatorColor ||
      oldDelegate.slotIndicatorTextStyle != slotIndicatorTextStyle ||
      oldDelegate.slotIndicatorBackgroundColor !=
          slotIndicatorBackgroundColor ||
      oldDelegate.slotUse24HourFormat != slotUse24HourFormat ||
      oldDelegate.showRegularHours != showRegularHours ||
      oldDelegate.floatingIndicatorTopInset != floatingIndicatorTopInset;
}

class OffSetAllDaysPainter extends CustomPainter {
  const OffSetAllDaysPainter(
    this.isToday,
    this.heightPerMinute,
    this.offTimesRanges,
    this.offTimesColor, {
    this.paintToday = false,
    this.plannerTimeMapper,
  });

  final bool isToday;
  final bool paintToday;
  final double heightPerMinute;
  final List<OffTimeRange> offTimesRanges;
  final Color offTimesColor;
  final PlannerTimeMapper? plannerTimeMapper;

  PlannerTimeMapper get _mapper =>
      plannerTimeMapper ?? PlannerTimeMapper(heightPerMinute: heightPerMinute);

  @override
  void paint(Canvas canvas, Size size) {
    if (!isToday || paintToday) {
      final paint = Paint()..color = offTimesColor;
      final mapper = _mapper;

      for (var range in offTimesRanges) {
        var startY = mapper.minuteToY(range.start.totalMinutes.toDouble());
        var endY = mapper.minuteToY(range.end.totalMinutes.toDouble());
        canvas.drawRect(
          Rect.fromPoints(Offset(0, startY), Offset(size.width, endY)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(OffSetAllDaysPainter oldDelegate) => true;
}

class ColumnPainter extends CustomPainter {
  const ColumnPainter({
    required this.width,
    required this.columnsParam,
    required this.lineColor,
  });

  final double width;
  final ColumnsParam columnsParam;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    var columnsTotalWidth = 0.0;
    final paint = Paint()..color = lineColor;
    for (var i = 0; i <= columnsParam.columns; i++) {
      canvas.drawLine(
        Offset(columnsTotalWidth, 0),
        Offset(columnsTotalWidth, size.height),
        paint,
      );

      if (i != columnsParam.columns) {
        var columnWidth = columnsParam.getColumSize(width, i);
        columnsTotalWidth += columnWidth;
      }
    }
  }

  @override
  bool shouldRepaint(ColumnPainter oldDelegate) => true;
}
