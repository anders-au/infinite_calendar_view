import 'package:flutter/material.dart';

import '../../events_planner.dart';
import '../../events/event.dart';
import '../../interactive_slot/slot_config.dart';
import '../../interactive_slot/slot_selection.dart';
import '../../painters/events_painters.dart';
import '../../utils/planner_time_mapper.dart';

class VerticalTimeIndicatorWidget extends StatelessWidget {
  const VerticalTimeIndicatorWidget({
    super.key,
    this.textDirection = TextDirection.ltr,
    required this.timesIndicatorsParam,
    required this.heightPerMinute,
    this.plannerTimeMapper,
    required this.currentHourIndicatorHourVisibility,
    required this.currentHourIndicatorColor,
    this.interactiveSlot,
    required this.slotInteractionConfig,
    this.floatingIndicatorTopInset = 0,
  });

  final TextDirection textDirection;
  final TimesIndicatorsParam timesIndicatorsParam;
  final double heightPerMinute;
  final PlannerTimeMapper? plannerTimeMapper;
  final bool currentHourIndicatorHourVisibility;
  final Color currentHourIndicatorColor;
  final CalendarSlot? interactiveSlot;
  final SlotInteractionConfig slotInteractionConfig;
  final double floatingIndicatorTopInset;

  PlannerTimeMapper get _timeMapper =>
      plannerTimeMapper ?? PlannerTimeMapper(heightPerMinute: heightPerMinute);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slot = interactiveSlot;
    final slotIndicatorEntries =
        slot == null ||
            slot.isAllDay ||
            !slotInteractionConfig.showTimeIndicators
        ? const <SlotTimeIndicator>[]
        : _slotTimeIndicators(slot);
    final slotMinutes = slotIndicatorEntries
        .map((indicator) => indicator.minute)
        .toList();
    final slotIndicatorColor =
        slotInteractionConfig.timeIndicatorColor ??
        slotInteractionConfig.accentColor ??
        theme.colorScheme.secondary;
    final rawCustomPainter = timesIndicatorsParam.timesIndicatorsCustomPainter
        ?.call(_timeMapper.heightPerMinute);
    final slotIndicators = SlotTimeIndicators(
      indicators: slotIndicatorEntries,
      color: slotIndicatorColor,
      backgroundColor: theme.colorScheme.surface,
      use24HourFormat: slotInteractionConfig.use24HourFormat,
      textStyle: slotInteractionConfig.timeIndicatorTextStyle,
    );
    final customPainter = rawCustomPainter is SlotAwareTimeIndicatorPainter
        ? (rawCustomPainter as SlotAwareTimeIndicatorPainter)
              .withSlotTimeIndicators(slotIndicators)
        : rawCustomPainter;
    final customPainterRendersSlot =
        rawCustomPainter is SlotAwareTimeIndicatorPainter;
    final defaultPainter = HoursPainter(
      heightPerMinute: _timeMapper.heightPerMinute,
      plannerTimeMapper: _timeMapper,
      textDirection: textDirection,
      showCurrentHour: currentHourIndicatorHourVisibility,
      hourColor: theme.colorScheme.outline,
      halfHourColor: theme.colorScheme.outlineVariant,
      quarterHourColor: theme.colorScheme.outlineVariant,
      currentHourIndicatorColor: currentHourIndicatorColor,
      slotIndicatorMinutes: customPainter == null ? slotMinutes : const [],
      slotIndicatorColor: slotIndicatorColor,
      slotIndicatorTextStyle: slotInteractionConfig.timeIndicatorTextStyle,
      slotIndicatorBackgroundColor: theme.colorScheme.surface,
      slotUse24HourFormat: slotInteractionConfig.use24HourFormat,
      floatingIndicatorTopInset: floatingIndicatorTopInset,
    );
    return Container(
      width: timesIndicatorsParam.timesIndicatorsWidth,
      color: theme.colorScheme.surface,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: timesIndicatorsParam.timesIndicatorsHorizontalPadding,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(foregroundPainter: customPainter ?? defaultPainter),
            if (customPainter != null &&
                !customPainterRendersSlot &&
                slotMinutes.isNotEmpty)
              CustomPaint(
                foregroundPainter: HoursPainter(
                  heightPerMinute: _timeMapper.heightPerMinute,
                  plannerTimeMapper: _timeMapper,
                  textDirection: textDirection,
                  showCurrentHour: false,
                  showRegularHours: false,
                  slotIndicatorMinutes: slotMinutes,
                  slotIndicatorColor: slotIndicatorColor,
                  slotIndicatorTextStyle:
                      slotInteractionConfig.timeIndicatorTextStyle,
                  slotIndicatorBackgroundColor: theme.colorScheme.surface,
                  slotUse24HourFormat: slotInteractionConfig.use24HourFormat,
                  floatingIndicatorTopInset: floatingIndicatorTopInset,
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<SlotTimeIndicator> _slotTimeIndicators(CalendarSlot slot) {
    final start = slot.startDateTime;
    final end = slot.endDateTime;
    final startMinute = start.hour * 60 + start.minute;
    var endMinute = end.hour * 60 + end.minute;
    if (endMinute == 0 && end.isAfter(start)) {
      endMinute = Event.minutesPerDay;
    }
    return [
      SlotTimeIndicator(
        minute: startMinute,
        boundary: SlotTimeIndicatorBoundary.start,
      ),
      if (startMinute != endMinute)
        SlotTimeIndicator(
          minute: endMinute,
          boundary: SlotTimeIndicatorBoundary.end,
        ),
    ];
  }
}
