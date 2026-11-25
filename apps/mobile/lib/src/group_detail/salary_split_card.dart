part of '../group_detail_screen.dart';

class _SalarySplitCard extends StatelessWidget {
  const _SalarySplitCard({required this.group, required this.onConfigure});
  final ExpenseGroup group;
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled
                ? colors.primaryContainer
                : colors.secondaryContainer.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.pie_chart_outline_rounded,
            color: enabled
                ? colors.onPrimaryContainer
                : colors.onSecondaryContainer,
          ),
        ),
        title: Text(
          enabled ? l10n.salarySplitsEnabled : l10n.salarySplits,
          style: theme.textTheme.titleSmall,
        ),
        subtitle: Text(
          message,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        trailing: TextButton(
          onPressed: onConfigure,
          child: Text(
            available || group.visibility == 'shared'
                ? l10n.configure
                : l10n.info,
          ),
        ),
      ),
    );
  }
}
