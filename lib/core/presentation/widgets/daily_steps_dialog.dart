import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/set_daily_steps_usecase.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/tracked_day_lock.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Asks for [day]'s step total, saves it as the day's Daily Steps and
/// refreshes every screen that shows the day's goal. [day] is a logical day
/// label.
Future<void> showDailyStepsDialog(BuildContext context, DateTime day) async {
  // Taken before the dialog opens, so steps typed on one profile are not
  // saved to another if the profile switches while it is open.
  final startedOn = ProfileStamp.now();
  final usecase = locator<SetDailyStepsUsecase>();
  final current = await usecase.getDailySteps(day);
  if (!context.mounted) return;
  final steps = await showDialog<int>(
    context: context,
    builder: (_) => DailyStepsDialog(initialSteps: current),
  );
  if (steps == null) return;
  if (!await usecase.setDailySteps(day, steps, startedOn: startedOn)) return;
  locator<HomeBloc>().add(const LoadItemsEvent());
  locator<DiaryBloc>().add(const LoadDiaryYearEvent());
  locator<CalendarDayBloc>().add(RefreshCalendarDayEvent());
}

/// [showDailyStepsDialog] for the current logical day.
Future<void> showTodaysStepsDialog(BuildContext context) async {
  final config = await locator<GetConfigUsecase>().getConfig();
  if (!context.mounted) return;
  await showDailyStepsDialog(
    context,
    DayBoundaryCalc.currentLogicalDayLabel(
      config.dayStartOffsetHours,
      config.dayStartOffsetMinutes,
    ),
  );
}

class DailyStepsDialog extends StatefulWidget {
  final int? initialSteps;

  const DailyStepsDialog({super.key, this.initialSteps});

  @override
  State<DailyStepsDialog> createState() => _DailyStepsDialogState();
}

class _DailyStepsDialogState extends State<DailyStepsDialog> {
  late final _controller = TextEditingController(
    text: widget.initialSteps?.toString() ?? '',
  );
  late int? _steps = widget.initialSteps;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(S.of(context).dailyStepsDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            identifier: 'daily-steps-input',
            child: TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: S.of(context).dailyStepsLabel,
                border: const OutlineInputBorder(),
              ),
              onChanged: (text) => setState(() => _steps = int.tryParse(text)),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            S.of(context).dailyStepsDialogHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(S.of(context).dialogCancelLabel),
        ),
        TextButton(
          onPressed: _steps == null
              ? null
              : () => Navigator.of(context).pop(_steps),
          child: Text(S.of(context).dialogOKLabel),
        ),
      ],
    );
  }
}
