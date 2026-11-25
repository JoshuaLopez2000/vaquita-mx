import 'package:flutter/material.dart';
import 'package:vaquita_mx/l10n/app_localizations.dart';
import 'package:vaquita_mx/src/theme/vaquita_theme.dart';

class SalaryInferenceNotice extends StatelessWidget {
  const SalaryInferenceNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final vColors = VaquitaColors.of(context);
    return Container(
      key: const Key('salary-inference-notice'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: vColors.warningContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: vColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.privacy_tip_outlined,
            color: vColors.onWarningContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              AppLocalizations.of(context)!.salaryInferenceDisclosure,
              style: TextStyle(color: vColors.onWarningContainer),
            ),
          ),
        ],
      ),
    );
  }
}
