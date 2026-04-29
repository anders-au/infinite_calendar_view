import 'package:flutter/material.dart';

import '../../events_planner.dart';
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
  });

  final TextDirection textDirection;
  final TimesIndicatorsParam timesIndicatorsParam;
  final double heightPerMinute;
  final PlannerTimeMapper? plannerTimeMapper;
  final bool currentHourIndicatorHourVisibility;
  final Color currentHourIndicatorColor;

  PlannerTimeMapper get _timeMapper => plannerTimeMapper ?? PlannerTimeMapper(heightPerMinute: heightPerMinute);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: timesIndicatorsParam.timesIndicatorsWidth,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: timesIndicatorsParam.timesIndicatorsHorizontalPadding),
        child: CustomPaint(
          foregroundPainter: timesIndicatorsParam.timesIndicatorsCustomPainter?.call(_timeMapper.heightPerMinute) ??
              HoursPainter(
                heightPerMinute: _timeMapper.heightPerMinute,
                plannerTimeMapper: _timeMapper,
                textDirection: textDirection,
                showCurrentHour: currentHourIndicatorHourVisibility,
                hourColor: Theme.of(context).colorScheme.outline,
                halfHourColor: Theme.of(context).colorScheme.outlineVariant,
                quarterHourColor: Theme.of(context).colorScheme.outlineVariant,
                currentHourIndicatorColor: currentHourIndicatorColor,
              ),
        ),
      ),
    );
  }
}
