import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/body_fat_reading_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/onboarding/presentation/widgets/onboarding_body_fat_page_body.dart';
import 'package:opennutritracker/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Shown in place of the app for a user who has no body fat reading, such
/// as one whose profile predates it. The calorie goal is calculated from
/// lean body mass, so there is no goal to show until they enter one.
class BodyFatRequiredScreen extends StatefulWidget {
  final UserEntity user;
  final VoidCallback onSaved;

  const BodyFatRequiredScreen({
    super.key,
    required this.user,
    required this.onSaved,
  });

  @override
  State<BodyFatRequiredScreen> createState() => _BodyFatRequiredScreenState();
}

class _BodyFatRequiredScreenState extends State<BodyFatRequiredScreen> {
  final _controller = TextEditingController();
  double? _percent;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    widget.user.bodyFatReading = BodyFatReadingEntity(
      bodyFatPercent: _percent!,
      weightKg: widget.user.weightKG,
    );
    await locator<ProfileBloc>().updateUser(widget.user);
    if (mounted) widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Dimens.spacing24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                S.of(context).bodyFatRequiredTitle,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: Dimens.spacing8),
              Text(
                S.of(context).bodyFatRequiredBody,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: Dimens.spacing24),
              Semantics(
                identifier: 'body-fat-required-input',
                child: BodyFatPercentField(
                  controller: _controller,
                  autofocus: true,
                  onChanged: (percent) => setState(() => _percent = percent),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: Semantics(
                  identifier: 'body-fat-required-save',
                  child: FilledButton(
                    onPressed: _percent == null || _saving ? null : _save,
                    child: Text(S.of(context).buttonSaveLabel),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
