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
    required this.isLoading,
    required this.errorMessage,
    this.navigationTarget,
  });

  factory AppState.fromStore(DemoStore store) => AppState(
        groups: List.unmodifiable(store.groups),
        contacts: List.unmodifiable(store.contacts),
        contactStatus: List.unmodifiable(store.contactStatus),
        invitations: List.unmodifiable(store.invitations),
        isLoading: store.isLoading,
        errorMessage: store.errorMessage,
        navigationTarget: store.takeRequestedTab(),
      );

  final List<ExpenseGroup> groups;
  final List<AppContact> contacts;
  final List<ContactStatus> contactStatus;
  final List<GroupInvitation> invitations;
  final bool isLoading;
  final String? errorMessage;
  final int? navigationTarget;
}
