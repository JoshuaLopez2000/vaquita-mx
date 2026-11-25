import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:vaquita_mx/l10n/app_localizations.dart';
import 'package:vaquita_mx/l10n/localized_error.dart';
import 'package:vaquita_mx/src/features/app/application/app_cubit.dart';
import 'package:vaquita_mx/src/models.dart';
import 'package:vaquita_mx/src/store.dart';
import 'package:vaquita_mx/src/theme/vaquita_theme.dart';
import 'package:vaquita_mx/src/widgets/payment_request_card.dart';
import 'package:vaquita_mx/src/widgets/vaquita_brand.dart';

class PaymentRequestDetailScreen extends StatefulWidget {
  const PaymentRequestDetailScreen({
    required this.store,
    required this.requestId,
    this.initialRequest,
    super.key,
  });

  final DemoStore store;
  final String requestId;
  final PaymentRequestItem? initialRequest;

  @override
  State<PaymentRequestDetailScreen> createState() =>
      _PaymentRequestDetailScreenState();
}

class _PaymentRequestDetailScreenState
    extends State<PaymentRequestDetailScreen> {
  PaymentRequestItem? _request;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _request = widget.initialRequest ??
        widget.store.paymentRequestById(widget.requestId);
    _hydrate();
  }

  Future<void> _hydrate() async {
    if (!widget.store.isAuthenticated) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    final fetched =
        await context.read<AppCubit>().loadPaymentRequestById(widget.requestId);
    if (!mounted) return;
    setState(() {
      if (fetched != null) {
        _request = fetched;
      } else if (widget.store.errorMessage == 'resource_not_found') {
        _request = null;
      }
      _loading = false;
    });
  }

  Future<void> _copyLink(PaymentRequestItem request) async {
    final l10n = AppLocalizations.of(context)!;
    await Clipboard.setData(ClipboardData(text: request.paymentUrl));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.paymentLinkCopied)),
    );
  }

  Future<void> _completeSimulatedPayment(PaymentRequestItem request) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _submitting = true);
    final completed =
        await context.read<AppCubit>().completeSimulatedPayment(request.id);
    if (!mounted) return;
    final updated = widget.store.paymentRequestById(request.id);
    setState(() {
      if (updated != null) _request = updated;
      _submitting = false;
    });
    if (completed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.simulatedPaymentCompleted)),
      );
    } else {
      final error = widget.store.errorMessage;
      final message = error != null
          ? localizedError(
              l10n,
              error,
              fallback: l10n.couldNotCompleteSimulatedPayment,
            )
          : l10n.couldNotCompleteSimulatedPayment;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  String _formatDate(BuildContext context, DateTime dateTime) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    return DateFormat.yMMMd(locale).add_jm().format(dateTime.toLocal());
  }

  String _resolveMemberName(
    PaymentRequestItem request, {
    required bool creditor,
  }) {
    final direct = creditor ? request.creditorName : request.debtorName;
    if (direct.isNotEmpty) return direct;
    final memberId = creditor ? request.creditorId : request.debtorId;
    for (final group in widget.store.groups) {
      if (group.id != request.groupId) continue;
      for (final member in group.members) {
        if (member.id == memberId) return member.name;
      }
    }
    return memberId;
  }

  String _resolveGroupTitle(PaymentRequestItem request) {
    if (request.groupName.isNotEmpty) {
      return request.groupEmoji.isNotEmpty
          ? '${request.groupEmoji} ${request.groupName}'
          : request.groupName;
    }
    for (final group in widget.store.groups) {
      if (group.id == request.groupId) {
        return group.emoji.isNotEmpty
            ? '${group.emoji} ${group.name}'
            : group.name;
      }
    }
    return request.groupId;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final request =
            _request ?? widget.store.paymentRequestById(widget.requestId);
        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.paymentRequestDetailsTitle),
            actions: [
              if (widget.store.isAuthenticated)
                IconButton(
                  tooltip: l10n.paymentRequestDetailsTitle,
                  onPressed: _loading ? null : _hydrate,
                  icon: const Icon(Icons.refresh_rounded),
                ),
            ],
          ),
          body: !widget.store.isAuthenticated
              ? Center(
                  child: VaquitaEmptyState(
                    icon: Icons.lock_outline_rounded,
                    title: l10n.paymentRequestNotFoundTitle,
                    description: l10n.paymentRequestSignInRequired,
                  ),
                )
              : _loading && request == null
                  ? const Center(child: CircularProgressIndicator())
                  : request == null
                      ? Center(
                          child: VaquitaEmptyState(
                            icon: Icons.receipt_long_outlined,
                            title: l10n.paymentRequestNotFoundTitle,
                            description: l10n.paymentRequestNotFoundDescription,
                          ),
                        )
                      : _buildBody(context, request),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, PaymentRequestItem request) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final vColors = VaquitaColors.of(context);
    final creditorName = _resolveMemberName(request, creditor: true);
    final debtorName = _resolveMemberName(request, creditor: false);
    final groupTitle = _resolveGroupTitle(request);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        Card(
          key: const Key('payment-request-demo-disclaimer'),
          color: vColors.warningContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: vColors.warning.withValues(alpha: 0.35)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: vColors.onWarningContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.paymentRequestDemoDisclaimerTitle,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: vColors.onWarningContainer,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.paymentRequestDemoDisclaimerBody,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: vColors.onWarningContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        groupTitle,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    PaymentRequestStatusChip(request: request),
                  ],
                ),
                const SizedBox(height: 16),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${formatMoney(request.amountCents)} ${request.currency}',
                    style: VaquitaTheme.money(
                      theme.textTheme.headlineMedium,
                      weight: FontWeight.w900,
                    ),
                  ),
                ),
                if (request.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    request.description,
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Divider(height: 1),
                ),
                _DetailRow(
                  label: l10n.paymentRequestCreditorLabel,
                  value: creditorName,
                ),
                const SizedBox(height: 10),
                _DetailRow(
                  label: l10n.paymentRequestDebtorLabel,
                  value: debtorName,
                ),
                if (request.expiresAt != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    l10n.paymentRequestExpiresAt(
                      _formatDate(context, request.expiresAt!),
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (request.isPaid && request.paidAt != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    l10n.paymentRequestPaidAt(
                      _formatDate(context, request.paidAt!),
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: vColors.positive,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (request.paymentUrl.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(height: 1),
                  ),
                  Text(
                    l10n.paymentLinkLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    request.paymentUrl,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (request.isPaid)
          _StatusExplanationCard(
            key: const Key('payment-request-state-explanation'),
            icon: Icons.check_circle_outline_rounded,
            color: vColors.positiveContainer,
            foreground: vColors.onPositiveContainer,
            message: l10n.paymentRequestPaidExplanation,
          )
        else if (request.isExpired)
          _StatusExplanationCard(
            key: const Key('payment-request-state-explanation'),
            icon: Icons.schedule_rounded,
            color: scheme.surfaceContainerHigh,
            foreground: scheme.onSurfaceVariant,
            message: l10n.paymentRequestExpiredExplanation,
          )
        else if (request.isFailed)
          _StatusExplanationCard(
            key: const Key('payment-request-state-explanation'),
            icon: Icons.error_outline_rounded,
            color: scheme.errorContainer,
            foreground: scheme.onErrorContainer,
            message: l10n.paymentRequestFailedExplanation,
          )
        else if (request.isDebtor) ...[
          FilledButton.icon(
            key: const Key('complete-simulated-payment-button'),
            onPressed: _submitting || !widget.store.isOnline
                ? null
                : () => _completeSimulatedPayment(request),
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_outline_rounded),
            label: Text(l10n.completeSimulatedPayment),
          ),
          if (!widget.store.isOnline) ...[
            const SizedBox(height: 8),
            Text(
              l10n.paymentRequestsRequireInternet,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ] else ...[
          _StatusExplanationCard(
            key: const Key('payment-request-waiting-debtor'),
            icon: Icons.hourglass_top_rounded,
            color: vColors.warningContainer,
            foreground: vColors.onWarningContainer,
            message: l10n.paymentRequestWaitingDebtor(debtorName),
          ),
        ],
        if (request.paymentUrl.isNotEmpty) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('share-payment-request-link-button'),
            onPressed: () => _copyLink(request),
            icon: const Icon(Icons.share_outlined),
            label: Text(l10n.sharePaymentLink),
          ),
        ],
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusExplanationCard extends StatelessWidget {
  const _StatusExplanationCard({
    required this.icon,
    required this.color,
    required this.foreground,
    required this.message,
    super.key,
  });

  final IconData icon;
  final Color color;
  final Color foreground;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: foreground),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
