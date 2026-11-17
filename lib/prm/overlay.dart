import 'dart:math' as math;

import 'package:PiliPlus/prm/progress.dart';
import 'package:PiliPlus/prm/service.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// A read-only PRM decoration. Never derives progress from Bilibili history.
/// The optional listenable drives this same production widget in widget tests.
class PrmProgressOverlay extends StatelessWidget {
  const PrmProgressOverlay({
    super.key,
    required this.videoId,
    required this.child,
    this.service,
    this.summaryListenable,
    this.topRightBadge,
  });

  final String? videoId;
  final Widget child;
  final String? topRightBadge;
  final PrmProgressService? service;
  final ValueListenable<PrmProgressSummary?>? summaryListenable;

  @override
  Widget build(BuildContext context) => MediaQuery.withClampedTextScaling(
    // Cover metadata occupies a fixed-size image, unlike page text. Keep native
    // duration/badges compact too, so accessibility scaling cannot cover PRM.
    maxScaleFactor: 1,
    child: Builder(builder: _build),
  );

  Widget _build(BuildContext context) {
    if (summaryListenable case final source?) {
      return ValueListenableBuilder<PrmProgressSummary?>(
        valueListenable: source,
        child: child,
        builder: (context, summary, child) =>
            _decorate(context, summary, child!),
      );
    }
    final source = service ?? PrmProgressService.instance;
    return ListenableBuilder(
      listenable: source,
      child: child,
      builder: (context, child) =>
          _decorate(context, source.summaryFor(videoId), child!),
    );
  }

  Widget _decorate(
    BuildContext context,
    PrmProgressSummary? summary,
    Widget child,
  ) {
    if (summary == null) return child;
    return Tooltip(
      message: 'PRM · ${summary.badge}\n${summary.tooltip}',
      // Hover remains available on desktop; mobile long-press belongs to the
      // cover's existing save/menu gesture, never to this decoration.
      triggerMode: TooltipTriggerMode.manual,
      ignorePointer: true,
      excludeFromSemantics: true,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: Semantics(
                label: 'PRM · ${summary.badge}，${summary.tooltip}',
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Reserve the right side for native badges, the bottom for
                    // duration/stats. Scale down only when the cover is tiny.
                    var availableWidth = constraints.maxWidth * 0.62 - 4;
                    if (topRightBadge?.isNotEmpty == true) {
                      final native = TextPainter(
                        text: TextSpan(
                          text: topRightBadge,
                          style: DefaultTextStyle.of(context).style.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        textDirection: Directionality.of(context),
                        textScaler: MediaQuery.textScalerOf(context),
                      )..layout();
                      availableWidth = math.min(
                        availableWidth,
                        constraints.maxWidth - native.width - 28,
                      );
                      native.dispose();
                    }
                    final badgeWidth = math.max(0.0, availableWidth);
                    final badgeHeight = math.max(
                      0.0,
                      math.min(
                        constraints.maxHeight * 0.45,
                        constraints.maxHeight - 28,
                      ),
                    );
                    final ratio = summary.ratio;
                    final compact = badgeWidth < 64;
                    final compactStatus = summary.badge == '已看完'
                        ? '看完'
                        : ratio != null && ratio.isFinite
                        ? '${(ratio.clamp(0.0, 1.0) * 100).round()}%'
                        : summary.badge.contains('分')
                        ? '分P'
                        : '记录';
                    return Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        if (badgeWidth > 0 && badgeHeight > 0)
                          Positioned(
                            top: 4,
                            left: 4,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: badgeWidth,
                                maxHeight: badgeHeight,
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.topLeft,
                                child: DecoratedBox(
                                  key: const ValueKey('prm-badge'),
                                  decoration: const BoxDecoration(
                                    color: Color(0xDD242424),
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(4),
                                    ),
                                  ),
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: compact ? 2 : 5,
                                      vertical: compact ? 2 : 3,
                                    ),
                                    child: Text(
                                      compact
                                          ? 'PRM\n$compactStatus'
                                          : 'PRM · ${summary.badge}',
                                      maxLines: compact ? 2 : 1,
                                      textAlign: compact
                                          ? TextAlign.center
                                          : TextAlign.start,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: compact ? 9 : 11,
                                        height: 1.1,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (ratio != null && ratio.isFinite)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: 3,
                            child: ClipRect(
                              child: ColoredBox(
                                color: const Color(0x66242424),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: FractionallySizedBox(
                                    key: const ValueKey('prm-progress'),
                                    widthFactor: ratio.clamp(0.0, 1.0),
                                    heightFactor: 1,
                                    child: const ColoredBox(
                                      color: Color(0xFFEF5350),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
