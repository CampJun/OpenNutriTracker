import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/body_fat_reading_entity.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Asks for the body fat percentage that, with the weight from the previous
/// page, makes the user's first body fat reading.
class OnboardingBodyFatPageBody extends StatefulWidget {
  final void Function(bool active, double? bodyFatPercent) setButtonContent;
  final double? initialBodyFatPercent;

  const OnboardingBodyFatPageBody({
    super.key,
    required this.setButtonContent,
    this.initialBodyFatPercent,
  });

  @override
  State<OnboardingBodyFatPageBody> createState() =>
      _OnboardingBodyFatPageBodyState();
}

class _OnboardingBodyFatPageBodyState extends State<OnboardingBodyFatPageBody> {
  late final _controller = TextEditingController(
    text: widget.initialBodyFatPercent?.toString() ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              S.of(context).bodyFatLabel,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              S.of(context).onboardingBodyFatQuestionSubtitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: Dimens.spacing16),
            Semantics(
              identifier: 'onboarding-body-fat-input',
              child: BodyFatPercentField(
                controller: _controller,
                onChanged: (percent) =>
                    widget.setButtonContent(percent != null, percent),
              ),
            ),
            const SizedBox(height: Dimens.spacing16),
            Text(
              S.of(context).bodyFatExplanation,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// A body fat percentage input that reports a value only when it is a number
/// within [BodyFatReadingEntity.minPercent]..[BodyFatReadingEntity.maxPercent].
class BodyFatPercentField extends StatelessWidget {
  final TextEditingController controller;
  final void Function(double? validPercent) onChanged;
  final bool autofocus;

  const BodyFatPercentField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.autofocus = false,
  });

  static double? parse(String text) {
    final value = double.tryParse(text.trim().replaceAll(',', '.'));
    if (value == null || !BodyFatReadingEntity.isValidPercent(value)) {
      return null;
    }
    return value;
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        labelText: S.of(context).bodyFatLabel,
        suffixText: '%',
        border: const OutlineInputBorder(),
      ),
      validator: (text) => text == null || text.isEmpty || parse(text) != null
          ? null
          : S
                .of(context)
                .bodyFatRangeError(
                  BodyFatReadingEntity.minPercent.toInt(),
                  BodyFatReadingEntity.maxPercent.toInt(),
                ),
      onChanged: (text) => onChanged(parse(text)),
    );
  }
}
