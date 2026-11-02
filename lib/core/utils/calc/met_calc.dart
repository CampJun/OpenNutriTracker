import 'package:opennutritracker/core/domain/entity/physical_activity_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';

class METCalc {
  /// Calculates total kcal with formula by the
  /// '2024 Adult Compendium of Physical Activities'
  /// https://pubmed.ncbi.nlm.nih.gov/38242596/
  /// by Herrmann et al.
  /// kcal = (MET - 1) x weight in kg x duration in hours
  ///
  /// Net of resting burn: 1 MET is the resting rate, which TDEE already
  /// counts for the whole day, so only the energy above it is credited.
  static double getTotalBurnedKcal(
    UserEntity userEntity,
    PhysicalActivityEntity physicalActivityEntity,
    double durationMin,
  ) {
    final netMets = (physicalActivityEntity.mets - 1).clamp(
      0.0,
      double.infinity,
    );
    return netMets * userEntity.weightKG * durationMin / 60;
  }
}
