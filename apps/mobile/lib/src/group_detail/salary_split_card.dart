part of '../group_detail_screen.dart';

class _SalarySplitCard extends StatelessWidget {
  const _SalarySplitCard({required this.group, required this.onConfigure});
  final ExpenseGroup group;
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final enabled = group.salarySplitEnabled;
    final available = group.salarySplitAvailable;
    final message = enabled
        ? l10n.salaryEnabledDescription
        : available
            ? l10n.salaryAvailableDescription
            : group.visibility == 'shared'
                ? l10n.salaryWaitingDescription
                : l10n.salarySharedGroupRequired;
    return Card(
        child: ListTile(
      leading: Icon(Icons.pie_chart_outline_rounded,
          color: Theme.of(context).colorScheme.primary),
      title: Text(enabled ? l10n.salarySplitsEnabled : l10n.salarySplits),
      subtitle: Text(message),
      trailing: TextButton(
          onPressed: onConfigure,
          child: Text(available || group.visibility == 'shared'
              ? l10n.configure
              : l10n.info)),
    ));
  }
}
