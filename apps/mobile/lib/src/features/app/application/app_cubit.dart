import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vaquita_mx/src/features/app/application/app_state.dart';
import 'package:vaquita_mx/src/models.dart';
import 'package:vaquita_mx/src/store.dart';

/// Application use-case coordinator. It is the only presentation-state
/// listener for the existing repository boundary and emits immutable states.
class AppCubit extends Cubit<AppState> {
  AppCubit(this.store) : super(AppState.fromStore(store)) {
    store.addListener(_publish);
  }

  final DemoStore store;

  void _publish() => emit(AppState.fromStore(store));

  Future<void> loadGroups() => store.load();
  Future<bool> syncLocalGroups({bool enable = false}) =>
      store.syncLocalGroups(enable: enable);
  Future<bool> syncPendingMutations({bool retryFailed = false}) =>
      store.syncPendingMutations(retryFailed: retryFailed);
  Future<void> discardFailedMutation(String mutationId) =>
      store.discardFailedMutation(mutationId);
  Future<void> loadInbox({String? paymentRequestOrientation}) async {
    await Future.wait([
      store.loadStatus(),
      store.loadInvitations(),
      store.loadPaymentRequests(orientation: paymentRequestOrientation),
    ]);
  }

  Future<PaymentRequestPage?> loadPaymentRequests({
    String? status,
    String? orientation,
    String? groupId,
    int limit = 50,
    bool append = false,
  }) =>
      store.loadPaymentRequests(
        status: status,
        orientation: orientation,
        groupId: groupId,
        limit: limit,
        append: append,
      );

  Future<PaymentRequestItem?> loadPaymentRequestById(String requestId) =>
      store.loadPaymentRequestById(requestId);

  Future<bool> completeSimulatedPayment(String requestId) =>
      store.completeSimulatedPayment(requestId);

  Future<bool> createGroup({
    required String name,
    required List<String> memberNames,
    required String emoji,
    required String visibility,
    required bool salarySplitEnabled,
    required List<Map<String, String>>? members,
  }) =>
      store.createGroup(
        name: name,
        memberNames: memberNames,
        emoji: emoji,
        visibility: visibility,
        salarySplitEnabled: salarySplitEnabled,
        members: members,
      );

  Future<bool> respondToInvitation(String groupId, bool accept) =>
      store.respondInvitation(groupId, accept);

  Future<bool> settleBalance({
    required String groupId,
    required String memberId,
    int? amountCents,
    String? replacesSettlementId,
  }) =>
      store.settleBalance(
        groupId: groupId,
        memberId: memberId,
        amountCents: amountCents,
        replacesSettlementId: replacesSettlementId,
      );

  Future<bool> confirmReceivedPayment({
    required String groupId,
    required String debtorId,
    int? amountCents,
    String? replacesSettlementId,
  }) =>
      store.confirmReceivedPayment(
        groupId: groupId,
        debtorId: debtorId,
        amountCents: amountCents,
        replacesSettlementId: replacesSettlementId,
      );

  Future<bool> reverseSettlement({
    required String groupId,
    required String settlementId,
    required String reason,
  }) =>
      store.reverseSettlement(
        groupId: groupId,
        settlementId: settlementId,
        reason: reason,
      );

  Future<bool> requestPayment({
    required String groupId,
    required String debtorId,
    required int amountCents,
    String description = 'Group balance settlement',
  }) =>
      store.requestPayment(
        groupId: groupId,
        debtorId: debtorId,
        amountCents: amountCents,
        description: description,
      );

  Future<bool> addExpense({
    required String groupId,
    required String description,
    required int amountCents,
    required String payerId,
    required List<ExpensePayer> payers,
    required List<String> participantIds,
    required String splitMode,
    List<ExpenseShare> shares = const [],
    List<ExpensePercentage> percentages = const [],
    bool splitOverpayment = true,
    String? replacesExpenseId,
  }) =>
      store.addExpense(
        groupId: groupId,
        description: description,
        amountCents: amountCents,
        payerId: payerId,
        payers: payers,
        participantIds: participantIds,
        splitMode: splitMode,
        shares: shares,
        percentages: percentages,
        splitOverpayment: splitOverpayment,
        replacesExpenseId: replacesExpenseId,
      );

  Future<bool> reverseExpense({
    required String groupId,
    required String expenseId,
    required String reason,
  }) =>
      store.reverseExpense(
        groupId: groupId,
        expenseId: expenseId,
        reason: reason,
      );

  Future<bool> updateGroup(String groupId, Map<String, dynamic> input) =>
      store.updateGroup(groupId, input);

  Future<bool> addMember(String groupId, String name, String phone) =>
      store.addMember(groupId, name, phone);

  Future<bool> updateMember(
          String groupId, String memberId, Map<String, dynamic> input) =>
      store.updateMember(groupId, memberId, input);

  Future<bool> removeMember(String groupId, String memberId) =>
      store.removeMember(groupId, memberId);

  Future<void> findContacts(List<String> phones) => store.findContacts(phones);
  Future<void> loadContacts() => store.loadContacts();
  Future<bool> saveContact(String name, String phone) =>
      store.saveContact(name, phone);
  Future<bool> saveContacts(List<AppContact> contacts) =>
      store.saveContacts(contacts);
  Future<bool> removeContact(String contactId) =>
      store.removeContact(contactId);

  void showMovements() => store.showMovements();

  @override
  Future<void> close() {
    store.removeListener(_publish);
    return super.close();
  }
}
