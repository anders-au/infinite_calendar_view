import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_calendar_view/infinite_calendar_view.dart';

void main() {
  group('CalendarPresentationPolicy', () {
    final start = DateTime(2026, 9, 12, 20, 9);

    test('keeps spans at or below 24 hours out of the day lane', () {
      expect(
        CalendarPresentationPolicy.rendersInFullDayRegion(
          start: start,
          end: start.add(const Duration(hours: 24)),
          sourceIsAllDay: false,
        ),
        isFalse,
      );
    });

    test('uses the day lane for spans longer than 24 hours', () {
      expect(
        CalendarPresentationPolicy.rendersInFullDayRegion(
          start: start,
          end: start.add(const Duration(hours: 24, minutes: 1)),
          sourceIsAllDay: false,
        ),
        isTrue,
      );
    });

    test('preserves an explicit source all-day classification', () {
      expect(
        CalendarPresentationPolicy.rendersInFullDayRegion(
          start: start,
          end: start.add(const Duration(hours: 1)),
          sourceIsAllDay: true,
        ),
        isTrue,
      );
    });

    test(
      'CalendarSlot derives the day lane without changing source semantics',
      () {
        final slot = CalendarSlot(
          columnIndex: 0,
          initialStartDate: start,
          startDateTime: start,
          duration: const Duration(hours: 48, minutes: 1),
        );

        expect(slot.isAllDay, isFalse);
        expect(slot.rendersInFullDayRegion, isTrue);
        expect(slot.startDateTime, start);
        expect(
          slot.endDateTime,
          start.add(const Duration(hours: 48, minutes: 1)),
        );
      },
    );
  });

  group('CalendarDaySpanGeometry', () {
    test('renders a midnight-to-midnight span edge to edge', () {
      final geometry = CalendarDaySpanGeometry(
        start: DateTime(2026, 9, 12),
        end: DateTime(2026, 9, 15),
        dayWidth: 100,
        leadingPadding: 0,
        trailingGap: 0,
        endIsExclusive: true,
        usePartialDayBounds: true,
      );

      expect(geometry.dayCount, 3);
      expect(geometry.startInset, 0);
      expect(geometry.endInset, 0);
      expect(geometry.naturalLeft(0), 0);
      expect(geometry.naturalWidth, 300);
    });

    test('insets non-midnight start and end by their day fractions', () {
      final geometry = CalendarDaySpanGeometry(
        start: DateTime(2026, 9, 12, 6),
        end: DateTime(2026, 9, 14, 12),
        dayWidth: 100,
        leadingPadding: 4,
        trailingGap: 3,
        endIsExclusive: true,
        usePartialDayBounds: true,
      );

      expect(geometry.dayCount, 3);
      expect(geometry.startInset, closeTo(25, 0.001));
      expect(geometry.endInset, closeTo(50, 0.001));
      expect(geometry.naturalLeft(0), closeTo(29, 0.001));
      expect(geometry.naturalWidth, closeTo(214, 0.001));
    });

    test('does not add a day for an exclusive midnight end', () {
      final geometry = CalendarDaySpanGeometry(
        start: DateTime(2026, 9, 12, 20, 9),
        end: DateTime(2026, 9, 15),
        dayWidth: 100,
        leadingPadding: 0,
        trailingGap: 0,
        endIsExclusive: true,
        usePartialDayBounds: true,
      );

      expect(geometry.dayCount, 3);
      expect(geometry.endInset, 0);
    });

    test('rejects invalid bounds', () {
      expect(
        () => CalendarDaySpanGeometry(
          start: DateTime(2026, 9, 12),
          end: DateTime(2026, 9, 12),
          dayWidth: 100,
          leadingPadding: 0,
          trailingGap: 0,
          endIsExclusive: true,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
