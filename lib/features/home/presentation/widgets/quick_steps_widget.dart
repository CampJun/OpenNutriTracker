import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/daily_steps_dialog.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/energy_display.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Daily Steps chip beside the weight and water chips: today's steps and the
/// kcal they add to the goal, tap to enter the tracker's total.
class QuickStepsWidget extends StatelessWidget {
  /// Today's activities, from which the Daily Steps row (if any) is read.
  final List<UserActivityEntity> todaysActivities;

  const QuickStepsWidget({super.key, required this.todaysActivities});

  @override
  Widget build(BuildContext context) {
    final stepsRow = todaysActivities
        .where((a) => a.physicalActivityEntity.isSteps)
        .firstOrNull;
    final label = stepsRow == null
        ? S.of(context).dailyStepsLabel
        : S
              .of(context)
              .dailyStepsChipValue(
                NumberFormat.decimalPattern(
                  Localizations.localeOf(context).toString(),
                ).format(stepsRow.steps ?? 0),
                EnergyDisplay.formatWithUnit(context, stepsRow.burnedKcal),
              );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final accent = Theme.of(context).colorScheme.primary;
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      identifier: 'home-steps-chip',
      child: Material(
        color: Colors.transparent,
        borderRadius: Dimens.borderRadiusM,
        child: InkWell(
          borderRadius: Dimens.borderRadiusM,
          onTap: () => showTodaysStepsDialog(context),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Dimens.spacing12,
              vertical: Dimens.spacing8,
            ),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: Dimens.borderRadiusM,
              border: Border.all(color: palette.border, width: Dimens.hairline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.directions_walk_rounded,
                  size: 18,
                  color: palette.textMuted,
                ),
                const SizedBox(width: Dimens.spacing8),
                Text(
                  label,
                  style: textTheme.labelLarge?.copyWith(
                    color: palette.textStrong,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: Dimens.spacing4),
                Icon(Icons.edit_rounded, size: 16, color: accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
