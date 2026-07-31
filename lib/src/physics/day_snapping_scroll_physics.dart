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
    final simulationTolerance = toleranceFor(position);

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
      if ((snappedEnd - position.pixels).abs() < simulationTolerance.distance) {
        return null;
      }
      return ScrollSpringSimulation(
        super.spring,
        position.pixels,
        snappedEnd,
        0,
        tolerance: simulationTolerance,
      );
    }

    // Find where the simulation would naturally end.
    final double naturalEnd = simulation.x(double.infinity);

    // Determine the target boundary.
    //
    // A deliberate fling keeps the parent's natural travel distance, rounded
    // to a snap boundary. This matters when one boundary is only a fraction
    // of the viewport, as it is in multi-day planner layouts.
    final double snappedEnd;
    if (velocity > directionalVelocityThreshold) {
      final naturalBoundary = (naturalEnd / pageSize).round() * pageSize;
      final nextBoundary =
          ((position.pixels / pageSize).floor() + 1) * pageSize;
      snappedEnd = naturalBoundary < nextBoundary
          ? nextBoundary
          : naturalBoundary;
    } else if (velocity < -directionalVelocityThreshold) {
      final naturalBoundary = (naturalEnd / pageSize).round() * pageSize;
      final previousBoundary =
          ((position.pixels / pageSize).ceil() - 1) * pageSize;
      snappedEnd = naturalBoundary > previousBoundary
          ? previousBoundary
          : naturalBoundary;
    } else {
      // Gentle fling or near-stop — snap to whichever boundary the
      // drag actually left the viewport nearest. This avoids light
      // swipes coasting into a page transition.
      snappedEnd = (position.pixels / pageSize).round() * pageSize;
    }

    if ((snappedEnd - naturalEnd).abs() < simulationTolerance.distance) {
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
      tolerance: simulationTolerance,
    );
  }
}
