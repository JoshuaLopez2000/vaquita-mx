import 'package:vaquita_mx/src/models.dart';
import 'package:vaquita_mx/src/store.dart';

/// Immutable presentation snapshot. Widgets consume this through BlocBuilder
/// instead of listening to the mutable data store directly.
class AppState {
  const AppState({
    required this.groups,
    required this.contacts,
    required this.contactStatus,
    required this.invitations,
    required this.pendingMutations,
    required this.failedMutations,
    required this.isOnline,
    required this.isLoading,
    required this.errorMessage,
    required this.user,
    this.navigationTarget,
  });

  factory AppState.fromStore(DemoStore store) => AppState(
        groups: List.unmodifiable(store.groups),
        contacts: List.unmodifiable(store.contacts),
        contactStatus: List.unmodifiable(store.contactStatus),
        invitations: List.unmodifiable(store.invitations),
        pendingMutations: store.pendingMutations,
        failedMutations: store.failedMutations,
        isOnline: store.isOnline,
        isLoading: store.isLoading,
        errorMessage: store.errorMessage,
        user: store.authenticatedUser,
        navigationTarget: store.takeRequestedTab(),
      );

  final List<ExpenseGroup> groups;
  final List<AppContact> contacts;
  final List<ContactStatus> contactStatus;
  final List<GroupInvitation> invitations;
  final List<PendingMutation> pendingMutations;
  final List<PendingMutation> failedMutations;
  final bool isOnline;
  final bool isLoading;
  final String? errorMessage;
  final AppUser? user;
  final int? navigationTarget;
}
