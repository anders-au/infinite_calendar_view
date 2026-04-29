import 'package:flutter/material.dart';

import '../../infinite_calendar_view.dart';
import '../utils/planner_time_mapper.dart';

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

  PlannerTimeMapper get _mapper => plannerTimeMapper ?? PlannerTimeMapper(heightPerMinute: heightPerMinute);

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
        canvas.drawLine(Offset(0, halfHourY), Offset(size.width, halfHourY), halfHourPaint);
      }

      if (drawQuarterHour && heightPerMinute > 2) {
        final quarterHourY15 = mapper.minuteToY((startMinute + 15).toDouble());
        final quarterHourY45 = mapper.minuteToY((startMinute + 45).toDouble());
        canvas.drawLine(Offset(0, quarterHourY15), Offset(size.width, quarterHourY15), quarterHourPaint);
        canvas.drawLine(Offset(0, quarterHourY45), Offset(size.width, quarterHourY45), quarterHourPaint);
      }
    }
    // draw 24:00
    final dayEndY = mapper.minuteToY((24 * 60).toDouble());
    canvas.drawLine(Offset(0, dayEndY), Offset(size.width, dayEndY), hourPaint);

    if (drawVerticalLeftLine) {
      canvas.drawLine(Offset(0, 0), Offset(0, size.height), verticalPaint);
    }
    if (drawVerticalRightLine) {
      canvas.drawLine(Offset(size.width, 0), Offset(size.width, size.height), verticalPaint);
    }
  }

  @override
  bool shouldRepaint(LinesPainter oldDelegate) => false;
}

class TimeIndicatorPainter extends CustomPainter {
  const TimeIndicatorPainter(this.heightPerMinute, this.isToday, this.color, {this.plannerTimeMapper});

  final double heightPerMinute;
  final bool isToday;
  final Color color;
  final PlannerTimeMapper? plannerTimeMapper;

  PlannerTimeMapper get _mapper => plannerTimeMapper ?? PlannerTimeMapper(heightPerMinute: heightPerMinute);

  @override
  void paint(Canvas canvas, Size size) {
    var currentTime = DateTime.now();

    // draw current time line
    if (isToday) {
      final currentTimePaint = Paint()
        ..color = color
        ..strokeWidth = 0.75;
      var currentTimeLineY = _mapper.minuteToY((currentTime.hour * 60 + currentTime.minute).toDouble());
      canvas.drawLine(Offset(0, currentTimeLineY), Offset(size.width, currentTimeLineY), currentTimePaint);
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
  final double halfHourMinHeightPerMinute;
  final double quarterHourMinHeightPerMinute;
  final TextPainter Function(TimeOfDay time, Color defaultColor)? textPainterBuilder;

  PlannerTimeMapper get _mapper => plannerTimeMapper ?? PlannerTimeMapper(heightPerMinute: heightPerMinute);

  @override
  void paint(Canvas canvas, Size size) {
    final mapper = _mapper;

    // draw currentHour
    var currentTime = TimeOfDay.now();
    if (showCurrentHour) {
      drawHour(canvas, size, currentTime, mapper.minuteToY(currentTime.totalMinutes.toDouble()), currentHourIndicatorColor);
    }

    // draw normal hour
    for (var i = 0; i <= 23; i++) {
      // hour
      final hourY = mapper.minuteToY((i * 60).toDouble()) + 4;
      if (!isHideByCurrentTime(currentTime, hourY)) {
        drawHour(canvas, size, TimeOfDay(hour: i, minute: 0), hourY, hourColor);
      }

      // half
      final halfY = mapper.minuteToY(((i * 60) + 30).toDouble()) + 4;
      if (heightPerMinute > halfHourMinHeightPerMinute && !isHideByCurrentTime(currentTime, halfY)) {
        drawHour(canvas, size, TimeOfDay(hour: i, minute: 30), halfY, halfHourColor);
      }

      // quart15
      final quarterY15 = mapper.minuteToY(((i * 60) + 15).toDouble()) + 4;
      if (heightPerMinute > quarterHourMinHeightPerMinute && !isHideByCurrentTime(currentTime, quarterY15)) {
        drawHour(canvas, size, TimeOfDay(hour: i, minute: 15), quarterY15, quarterHourColor);
      }

      // quart45
      final quarterY45 = mapper.minuteToY(((i * 60) + 45).toDouble()) + 4;
      if (heightPerMinute > quarterHourMinHeightPerMinute && !isHideByCurrentTime(currentTime, quarterY45)) {
        drawHour(canvas, size, TimeOfDay(hour: i, minute: 45), quarterY45, quarterHourColor);
      }
    }

    // 24:00 hour
    final hourY = mapper.minuteToY((24 * 60).toDouble()) + 4;
    if (!isHideByCurrentTime(currentTime, hourY)) {
      drawHour(canvas, size, TimeOfDay(hour: 24, minute: 0), hourY, hourColor);
    }
  }

  bool isHideByCurrentTime(TimeOfDay currentTime, double y) {
    final currentY = _mapper.minuteToY(currentTime.totalMinutes.toDouble());
    return showCurrentHour && (currentY - y).abs() <= 10;
  }

  void drawHour(
    Canvas canvas,
    Size size,
    TimeOfDay time,
    double y,
    Color color,
  ) {
    var textPainter = textPainterBuilder?.call(time, color) ?? getDefaultTextPainter(time, color);
    textPainter.layout(
      minWidth: size.width,
      maxWidth: size.width,
    );
    textPainter.paint(canvas, Offset(0, y));
  }

  TextPainter getDefaultTextPainter(TimeOfDay time, Color color) {
    return TextPainter(
      text: TextSpan(
        text: "${time.hour.toTimeText()}:${time.minute.toTimeText()}",
        style: TextStyle(color: color, fontSize: 12),
      ),
      textDirection: textDirection,
      textAlign: textDirection == TextDirection.ltr ? TextAlign.right : TextAlign.left,
    );
  }

  @override
  bool shouldRepaint(HoursPainter oldDelegate) => false;
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

  PlannerTimeMapper get _mapper => plannerTimeMapper ?? PlannerTimeMapper(heightPerMinute: heightPerMinute);

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
      canvas.drawLine(Offset(columnsTotalWidth, 0), Offset(columnsTotalWidth, size.height), paint);

      if (i != columnsParam.columns) {
        var columnWidth = columnsParam.getColumSize(width, i);
        columnsTotalWidth += columnWidth;
      }
    }
  }

  @override
  bool shouldRepaint(ColumnPainter oldDelegate) => true;
}
