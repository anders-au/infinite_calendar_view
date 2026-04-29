import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_calendar_view/src/utils/planner_time_mapper.dart';

void main() {
  group('PlannerTimeMapper', () {
    test('matches legacy linear behavior when hourCellGapPx is zero', () {
      const mapper = PlannerTimeMapper(heightPerMinute: 1.25, hourCellGapPx: 0);
      expect(mapper.minuteToY(0), 0);
      expect(mapper.minuteToY(60), 75);
      expect(mapper.minuteToY(720), 900);
      expect(mapper.minuteToY(1439), closeTo(1798.75, 0.0001));
      expect(mapper.totalDayHeight(), 24 * 60 * 1.25);
    });

    test('applies inter-hour gap in forward mapping and day height', () {
      const mapper = PlannerTimeMapper(heightPerMinute: 1, hourCellGapPx: 8);
      expect(mapper.minuteToY(59), 59);
      expect(mapper.minuteToY(60), 68);
      expect(mapper.minuteToY(12 * 60), 12 * (60 + 8));
      expect(mapper.totalDayHeight(), (24 * 60) + (23 * 8));
    });

    test('inverse maps gap to nearest side', () {
      const mapper = PlannerTimeMapper(heightPerMinute: 1, hourCellGapPx: 10);
      // Gap after first hour starts at y = 60 and ends at y = 70.
      expect(mapper.yToMinute(61), closeTo(59.999, 0.0001));
      expect(mapper.yToMinute(69), 60);
      // Tie goes backward for deterministic behavior.
      expect(mapper.yToMinute(65), closeTo(59.999, 0.0001));
    });

    test('round-trips minute->y->minute across day with gaps', () {
      const mapper = PlannerTimeMapper(heightPerMinute: 0.9, hourCellGapPx: 6);
      const sampleMinutes = <double>[0, 1, 59, 60, 61, 12 * 60, 18 * 60, 23 * 60 + 30, 1439];

      for (final minute in sampleMinutes) {
        final y = mapper.minuteToY(minute);
        final back = mapper.yToMinute(y);
        expect(back, closeTo(minute, 0.0001));
      }
    });
  });
}
