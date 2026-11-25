import 'package:flutter/material.dart';
import 'package:vaquita_mx/l10n/app_localizations.dart';
import 'package:vaquita_mx/src/models.dart';
import 'package:vaquita_mx/src/theme/vaquita_theme.dart';

String paymentRequestStatusLabel(
  AppLocalizations l10n,
  PaymentRequestItem request,
) {
  return switch (request.effectiveStatus) {
    PaymentRequestItem.statusPaid => l10n.paymentRequestStatusPaid,
    PaymentRequestItem.statusExpired => l10n.paymentRequestStatusExpired,
    PaymentRequestItem.statusFailed => l10n.paymentRequestStatusFailed,
    _ => l10n.paymentRequestStatusPending,
  };
}

class PaymentRequestStatusChip extends StatelessWidget {
  const PaymentRequestStatusChip({required this.request, super.key});

  final PaymentRequestItem request;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final vColors = VaquitaColors.of(context);
    final (Color bg, Color fg, IconData icon) =
        switch (request.effectiveStatus) {
      PaymentRequestItem.statusPaid => (
          vColors.positiveContainer,
          vColors.onPositiveContainer,
          Icons.check_circle_outline_rounded,
        ),
      PaymentRequestItem.statusExpired => (
          scheme.surfaceContainerHigh,
          scheme.onSurfaceVariant,
          Icons.schedule_rounded,
        ),
      PaymentRequestItem.statusFailed => (
          scheme.errorContainer,
          scheme.onErrorContainer,
          Icons.error_outline_rounded,
        ),
      _ => (
          vColors.warningContainer,
          vColors.onWarningContainer,
          Icons.hourglass_top_rounded,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              paymentRequestStatusLabel(l10n, request),
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: fg,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PaymentRequestCard extends StatelessWidget {
  const PaymentRequestCard({
    required this.request,
    required this.onTap,
    this.showGroup = true,
    super.key,
  });

  final PaymentRequestItem request;
  final VoidCallback onTap;
  final bool showGroup;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final vColors = VaquitaColors.of(context);
    final counterparty = request.isDebtor
        ? (request.creditorName.isNotEmpty
            ? request.creditorName
            : request.creditorId)
        : (request.debtorName.isNotEmpty
            ? request.debtorName
            : request.debtorId);
    final title = request.isDebtor
        ? l10n.paymentRequestToPayTo(counterparty)
        : l10n.paymentRequestRequestedFrom(counterparty);
    final subtitleParts = <String>[
      if (showGroup && request.groupName.isNotEmpty)
        '${request.groupEmoji.isNotEmpty ? '${request.groupEmoji} ' : ''}${request.groupName}',
      if (request.description.isNotEmpty) request.description,
    ];
    final iconBg = request.isDebtor
        ? vColors.negativeContainer
        : vColors.positiveContainer;
    final iconFg = request.isDebtor
        ? vColors.onNegativeContainer
        : vColors.onPositiveContainer;

    return Card(
      child: Semantics(
        button: true,
        child: InkWell(
          key: Key('payment-request-card-${request.id}'),
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    request.isDebtor
                        ? Icons.north_east_rounded
                        : Icons.south_west_rounded,
                    size: 20,
                    color: iconFg,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium,
                      ),
                      if (subtitleParts.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitleParts.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      PaymentRequestStatusChip(request: request),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatMoney(request.amountCents),
                      style: VaquitaTheme.money(
                        theme.textTheme.titleMedium,
                        color: request.isDebtor
                            ? vColors.negative
                            : vColors.positive,
                      ),
                    ),
                    Text(
                      request.currency,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
