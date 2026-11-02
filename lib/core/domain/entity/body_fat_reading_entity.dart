import 'package:equatable/equatable.dart';

/// A body fat percentage together with the body weight at the moment it was
/// measured. Lean body mass is derived from these two and stays pinned to
/// them: logging a new weight does not change it, only a new reading does.
/// See `CONTEXT.md` and `docs/adr/0001-katch-mcardle-replaces-iom-2005.md`.
class BodyFatReadingEntity extends Equatable {
  static const double minPercent = 3;
  static const double maxPercent = 70;

  final double bodyFatPercent;
  final double weightKg;

  const BodyFatReadingEntity({
    required this.bodyFatPercent,
    required this.weightKg,
  });

  double get leanBodyMassKg => weightKg * (1 - bodyFatPercent / 100);

  static bool isValidPercent(double percent) =>
      percent >= minPercent && percent <= maxPercent;

  @override
  List<Object?> get props => [bodyFatPercent, weightKg];
}
