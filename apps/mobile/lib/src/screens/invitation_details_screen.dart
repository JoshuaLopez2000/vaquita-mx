part of '../app.dart';

class InvitationDetailsScreen extends StatelessWidget {
  const InvitationDetailsScreen({required this.invitation, super.key});

  final GroupInvitation invitation;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.invitationDetails)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          CircleAvatar(
            radius: 32,
            child: Text(invitation.group.emoji,
                style: const TextStyle(fontSize: 28)),
          ),
          const SizedBox(height: 16),
          Text(invitation.group.name,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(l10n.sharedGroupInvitation, textAlign: TextAlign.center),
          const SizedBox(height: 32),
          Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text(l10n.responseRequired),
              subtitle: Text(l10n.returnToInbox),
            ),
          ),
        ],
      ),
    );
  }
}
