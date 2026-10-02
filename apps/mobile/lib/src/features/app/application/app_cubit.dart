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
  Future<void> loadInbox() async {
    await Future.wait([store.loadStatus(), store.loadInvitations()]);
  }

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
  }) =>
      store.settleBalance(groupId: groupId, memberId: memberId);

  Future<bool> requestPayment({
    required String groupId,
    required String debtorId,
    required int amountCents,
  }) =>
      store.requestPayment(
        groupId: groupId,
        debtorId: debtorId,
        amountCents: amountCents,
      );

  Future<bool> addExpense({
    required String groupId,
    required String description,
    required int amountCents,
    required String payerId,
    required List<String> participantIds,
    required String splitMode,
  }) =>
      store.addExpense(
        groupId: groupId,
        description: description,
        amountCents: amountCents,
        payerId: payerId,
        participantIds: participantIds,
        splitMode: splitMode,
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
