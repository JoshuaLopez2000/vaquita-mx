part of '../group_detail_screen.dart';

class _EmptyExpenses extends StatelessWidget {
  const _EmptyExpenses({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return VaquitaEmptyState(
      inCard: true,
      icon: Icons.receipt_long_outlined,
      title: l10n.noExpensesYet,
      action: OutlinedButton.icon(
        onPressed: onAdd,
        icon: const Icon(Icons.add_rounded),
        label: Text(l10n.addFirstExpense),
      ),
    );
  }
}
