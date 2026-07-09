// ──────────────────────────────────────────────────────────────────────────
// DaySnappingScrollPhysics — snaps flings to the nearest day-column
// boundary.  Unlike PageScrollPhysics (which snaps to viewport-width
// pages), this snaps to multiples of [pageSize], which is typically set
// to [dayWidth] for single-day snapping or [dayWidth * daysShowed] for
// bracket snapping.
// ──────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

class DaySnappingScrollPhysics extends ScrollPhysics {
  /// The width of one snap unit in logical pixels.
  final double pageSize;

  /// Minimum velocity (px/s) before a fling can force navigation to the
  /// next snap boundary.
  final double directionalVelocityThreshold;

  const DaySnappingScrollPhysics({
    required this.pageSize,
    this.directionalVelocityThreshold = 650.0,
    super.parent,
  });

  @override
  DaySnappingScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return DaySnappingScrollPhysics(
      pageSize: pageSize,
      directionalVelocityThreshold: directionalVelocityThreshold,
      parent: buildParent(ancestor),
    );
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    // Let the parent chain handle friction / bouncing.
    final Simulation? simulation = super.createBallisticSimulation(
      position,
      velocity,
    );

    if (simulation == null) {
      // No ballistic motion from the parent (e.g. the user lifted
      // their finger without flinging).  Snap to the nearest
      // boundary using the same spring as PageScrollPhysics so the
      // feel is identical.
      final snappedEnd = (position.pixels / pageSize).round() * pageSize;
      if ((snappedEnd - position.pixels).abs() < tolerance.distance) {
        return null;
      }
      return ScrollSpringSimulation(
        super.spring,
        position.pixels,
        snappedEnd,
        0,
        tolerance: tolerance,
      );
    }

    // Find where the simulation would naturally end.
    final double naturalEnd = simulation.x(double.infinity);

    // Determine the target boundary.
    //
    // When the user flings with enough velocity we commit to the next
    // boundary from the current drag position. This keeps navigation
    // deliberate without letting an ordinary fling skip multiple pages.
    final double snappedEnd;
    if (velocity > directionalVelocityThreshold) {
      // Strong forward fling — go to the next boundary.
      snappedEnd = ((position.pixels / pageSize).floor() + 1) * pageSize;
    } else if (velocity < -directionalVelocityThreshold) {
      // Strong backward fling — go to the previous boundary.
      snappedEnd = ((position.pixels / pageSize).ceil() - 1) * pageSize;
    } else {
      // Gentle fling or near-stop — snap to whichever boundary the
      // drag actually left the viewport nearest. This avoids light
      // swipes coasting into a page transition.
      snappedEnd = (position.pixels / pageSize).round() * pageSize;
    }

    if ((snappedEnd - naturalEnd).abs() < tolerance.distance) {
      // Already on or extremely close to a boundary — let the
      // original friction simulation play out naturally.
      return simulation;
    }

    // Drive from the current position to the snapped boundary with
    // the same initial velocity the fling had.  Uses the same spring
    // as PageScrollPhysics for a consistent feel across all snap modes.
    return ScrollSpringSimulation(
      super.spring,
      position.pixels,
      snappedEnd,
      velocity,
      tolerance: tolerance,
    );
  }
}
