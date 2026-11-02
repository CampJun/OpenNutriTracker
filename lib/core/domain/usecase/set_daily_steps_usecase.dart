import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/data/repository/user_activity_repository.dart';
import 'package:opennutritracker/core/domain/entity/physical_activity_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/log_user_activity_usecase.dart';
import 'package:opennutritracker/core/utils/calc/macro_calc.dart';
import 'package:opennutritracker/core/utils/calc/steps_calc.dart';
import 'package:opennutritracker/core/utils/id_generator.dart';
import 'package:opennutritracker/core/utils/tracked_day_lock.dart';

/// Sets a day's Daily Steps: the step tracker's total for that day, which
/// replaces anything entered earlier rather than adding to it.
///
/// Daily Steps are stored as one activity row with
/// [PhysicalActivityEntity.stepsCode], so the day's goal, the diary, the
/// reconciler and export all treat their kcal like any other activity's.
class SetDailyStepsUsecase {
  final UserActivityRepository _userActivityRepository;
  final AddTrackedDayUsecase _addTrackedDayUsecase;
  final LogUserActivityUsecase _logUserActivityUsecase;
  final GetUserUsecase _getUserUsecase;
  final ConfigRepository _configRepository;

  SetDailyStepsUsecase(
    this._userActivityRepository,
    this._addTrackedDayUsecase,
    this._logUserActivityUsecase,
    this._getUserUsecase,
    this._configRepository,
  );

  /// The steps entered for [day], or null if none were.
  Future<int?> getDailySteps(DateTime day) async =>
      (await _stepsRows(day)).firstOrNull?.steps;

  /// Replaces [day]'s steps with [steps]; zero clears them. [day] is a
  /// logical day label, as for [LogUserActivityUsecase.logActivity].
  Future<void> setDailySteps(DateTime day, int steps) async {
    final user = await _getUserUsecase.getUserData();
    await withTrackedDayLock(() async {
      final hasTrackedDay = await _addTrackedDayUsecase.hasTrackedDay(day);
      for (final row in await _stepsRows(day)) {
        await _userActivityRepository.deleteUserActivity(row);
        if (hasTrackedDay) {
          await _addTrackedDayUsecase.reduceDayCalorieGoal(day, row.burnedKcal);
          await _addTrackedDayUsecase.reduceDayMacroGoals(
            day,
            carbsAmount: MacroCalc.getTotalCarbsGoal(row.burnedKcal),
            fatAmount: MacroCalc.getTotalFatsGoal(row.burnedKcal),
            proteinAmount: MacroCalc.getTotalProteinsGoal(row.burnedKcal),
          );
        }
      }
      if (steps <= 0) return;

      final kcal = StepsCalc.netWalkingKcal(
        steps: steps,
        heightCM: user.heightCM,
        weightKG: user.weightKG,
      );
      await _logUserActivityUsecase.logActivity(
        UserActivityEntity(
          IdGenerator.getUniqueID(),
          0,
          kcal,
          day,
          PhysicalActivityEntity.steps,
          steps: steps,
        ),
        day: day,
      );
    });
  }

  Future<List<UserActivityEntity>> _stepsRows(DateTime day) async {
    final config = await _configRepository.getConfig();
    final rows = await _userActivityRepository.getAllUserActivityByDate(
      day,
      dayStartOffsetHours: config.dayStartOffsetHours,
      dayStartOffsetMinutes: config.dayStartOffsetMinutes,
    );
    return rows.where((row) => row.physicalActivityEntity.isSteps).toList();
  }
}
