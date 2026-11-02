import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/body_fat_reading_entity.dart';
import 'package:opennutritracker/features/onboarding/presentation/widgets/onboarding_body_fat_page_body.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Takes a new body fat percentage and returns it as a reading measured at
/// [currentWeightKg], which replaces the user's current one.
class SetBodyFatDialog extends StatefulWidget {
  final double currentWeightKg;
  final double? initialPercent;

  const SetBodyFatDialog({
    super.key,
    required this.currentWeightKg,
    this.initialPercent,
  });

  @override
  State<SetBodyFatDialog> createState() => _SetBodyFatDialogState();
}

class _SetBodyFatDialogState extends State<SetBodyFatDialog> {
  late final _controller = TextEditingController(
    text: widget.initialPercent?.toString() ?? '',
  );
  late double? _percent = widget.initialPercent;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(S.of(context).bodyFatLabel),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            identifier: 'body-fat-dialog-input',
            child: BodyFatPercentField(
              controller: _controller,
              autofocus: true,
              onChanged: (percent) => setState(() => _percent = percent),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            S.of(context).bodyFatNewReadingHint,
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
          onPressed: _percent == null
              ? null
              : () => Navigator.of(context).pop(
                  BodyFatReadingEntity(
                    bodyFatPercent: _percent!,
                    weightKg: widget.currentWeightKg,
                  ),
                ),
          child: Text(S.of(context).dialogOKLabel),
        ),
      ],
    );
  }
}
