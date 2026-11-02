import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/data/data_source/config_data_source.dart';
import 'package:opennutritracker/core/data/data_source/tracked_day_data_source.dart';
import 'package:opennutritracker/core/data/data_source/user_activity_data_source.dart';
import 'package:opennutritracker/core/data/data_source/user_activity_dbo.dart';
import 'package:opennutritracker/core/data/data_source/user_data_source.dart';
import 'package:opennutritracker/core/data/dbo/config_dbo.dart';
import 'package:opennutritracker/core/data/dbo/tracked_day_dbo.dart';
import 'package:opennutritracker/core/data/dbo/user_dbo.dart';
import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/data/repository/tracked_day_repository.dart';
import 'package:opennutritracker/core/data/repository/user_activity_repository.dart';
import 'package:opennutritracker/core/data/repository/user_repository.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_user_activity_usercase.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_macro_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/log_user_activity_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/set_daily_steps_usecase.dart';
import 'package:opennutritracker/core/utils/calc/calorie_goal_calc.dart';
import 'package:opennutritracker/core/utils/calc/steps_calc.dart';

import '../fixture/user_entity_fixtures.dart';
import '../helpers/fake_hive_db_provider.dart';
import '../helpers/hive_test_setup.dart';

void main() {
  final user = UserEntityFixtures.youngSedentaryMaleWantingToMaintainWeight;
  final day = DateTime(2026, 3, 10);

  late UserActivityRepository activityRepository;
  late TrackedDayRepository trackedDayRepository;
  late SetDailyStepsUsecase usecase;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    registerHiveAdaptersOnce();
  });

  setUp(() async {
    Hive.init('.');
    final configBox = await Hive.openBox<ConfigDBO>('steps_config_test');
    final activityBox = await Hive.openBox<UserActivityDBO>(
      'steps_activity_test',
    );
    final trackedDayBox = await Hive.openBox<TrackedDayDBO>(
      'steps_tracked_day_test',
    );
    final userBox = await Hive.openBox<UserDBO>('steps_user_test');
    for (final box in [configBox, activityBox, trackedDayBox, userBox]) {
      await box.clear();
    }

    final provider = FakeHiveDBProvider(
      configBox: configBox,
      userActivityBox: activityBox,
      trackedDayBox: trackedDayBox,
      userBox: userBox,
    );
    final configDataSource = ConfigDataSource(provider);
    await configDataSource.initializeConfig();
    final configRepository = ConfigRepository(configDataSource);
    activityRepository = UserActivityRepository(
      UserActivityDataSource(provider),
    );
    trackedDayRepository = TrackedDayRepository(TrackedDayDataSource(provider));
    final userRepository = UserRepository(UserDataSource(provider));
    await userRepository.updateUserData(user);

    final getKcalGoal = GetKcalGoalUsecase(
      userRepository,
      configRepository,
      activityRepository,
    );
    usecase = SetDailyStepsUsecase(
      activityRepository,
      AddTrackedDayUsecase(trackedDayRepository),
      LogUserActivityUsecase(
        AddUserActivityUsecase(activityRepository),
        AddTrackedDayUsecase(trackedDayRepository),
        getKcalGoal,
        GetMacroGoalUsecase(configRepository),
      ),
      GetUserUsecase(userRepository),
      configRepository,
    );
  });

  tearDown(() async {
    await Hive.close();
    await Hive.deleteFromDisk();
  });

  double stepsKcal(int steps) => StepsCalc.netWalkingKcal(
    steps: steps,
    heightCM: user.heightCM,
    weightKG: user.weightKG,
  );

  Future<double> dayGoal() async =>
      (await trackedDayRepository.getTrackedDay(day))!.calorieGoal;

  test('stores one steps row and raises the day goal by its kcal', () async {
    await usecase.setDailySteps(day, 10000);

    final rows = await activityRepository.getAllUserActivityByDate(day);
    expect(rows, hasLength(1));
    expect(rows.single.physicalActivityEntity.isSteps, isTrue);
    expect(rows.single.steps, 10000);
    expect(rows.single.burnedKcal, closeTo(stepsKcal(10000), 1e-9));
    expect(
      await dayGoal(),
      closeTo(CalorieGoalCalc.getTdee(user) + stepsKcal(10000), 1e-6),
    );
  });

  test(
    'a new number replaces the day total rather than adding to it',
    () async {
      await usecase.setDailySteps(day, 6000);
      await usecase.setDailySteps(day, 12000);

      final rows = await activityRepository.getAllUserActivityByDate(day);
      expect(rows, hasLength(1));
      expect(rows.single.steps, 12000);
      expect(
        await dayGoal(),
        closeTo(CalorieGoalCalc.getTdee(user) + stepsKcal(12000), 1e-6),
      );
    },
  );

  test('zero steps clears the day', () async {
    await usecase.setDailySteps(day, 8000);
    await usecase.setDailySteps(day, 0);

    expect(await activityRepository.getAllUserActivityByDate(day), isEmpty);
    expect(await dayGoal(), closeTo(CalorieGoalCalc.getTdee(user), 1e-6));
  });
}
