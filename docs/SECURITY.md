# Security baseline

This application handles financial metadata even though it does not hold funds. Treat group membership, expense descriptions, balances, phone numbers, and provider identifiers as sensitive.

## Required before public deployment

- TLS only; redirect or reject plaintext traffic.
- Authentication and authorization on every user or group resource.
- Password hashing with a deliberately chosen, reviewed password KDF. The current demo uses bcrypt; production should choose and document its final KDF and parameters before launch.
- Fifteen-minute access tokens, one-time rotated refresh tokens, and server-side revocation. Refresh-token reuse revokes the full device-session family.
- Rate limits on authentication, invitations, and payment operations.
- Encrypted secrets supplied by the hosting platform, never the mobile app.
- Database encryption at rest and encrypted backups.
- Structured audit events without bank data, tokens, or secrets in logs.
- Dependency, static-analysis, and container scanning in CI.

Scanner coverage, blocking thresholds, remediation deadlines, and exception
requirements are defined in [Security scanning](SECURITY_SCANNING.md).

## Payment controls

- Generate provider calls only from the server.
- Verify callback signatures before parsing business fields.
- Store each provider event ID under a unique database constraint.
- Process events transactionally and make retries safe.
- Match amount, currency, receiver, and correlation ID before settlement.
- Never accept a client-side `paid: true` value as proof of payment.
- In a shared group, only the authenticated creditor for an exact outstanding
  debtor/creditor relation may manually record a received payment. The API
  locks the group and revalidates the integer-centavo balance in the same
  transaction as the immutable settlement insert.
- In personal groups, only the owner may record a manual settlement. Local
  groups are personal and their settlement history remains on-device until
  the user opts in to sync.
- Reconciliation (issue #27) asks the provider adapter for its own record of
  pending requests through authenticated server-side credentials. A settled
  result is applied once per provider event, transactionally; divergent
  amount, currency, receiver, correlation ID, or repeated provider failures
  park the request in `payment_reconcile_events` for manual review instead of
  inventing settlements.
- Use compensating ledger entries instead of destructive edits.

## Group authorization matrix

Group membership stores one of two roles: `owner` or `member`. A role grants
permissions only while that membership is accepted, not declined, and not
removed. Hidden groups and unauthorized mutations return the same not-found
response so callers cannot enumerate group or member records.

| Action | Owner | Accepted member | Pending, declined, or removed |
| --- | --- | --- | --- |
| Read a personal group | Allow | Deny | Deny |
| Read a shared group | Allow | Allow | Deny |
| Change group settings | Allow | Deny | Deny |
| Invite, edit, or remove members | Allow | Deny | Deny |
| Change salary-sharing consent | Own membership only | Own membership only | Deny |
| Create an expense | Allow | Allow | Deny |
| Create a payment request | Exact creditor/debtor relation only | Exact creditor/debtor relation only | Deny |
| Record a manual settlement in a personal group | Owner only | Deny | Deny |
| Confirm received payment in a shared group | Exact creditor relation only | Exact creditor relation only | Deny |
| Accept or decline an invitation | Not applicable | Pending invitee only | Removed or declined: deny |

The owner role cannot be removed. Payment requests must match the exact
MXN-centavo amount in the server-derived creditor/debtor relation for active,
accepted members. A received-payment confirmation must also match the
authenticated member's creditor relationship with the named debtor.

## Mobile controls

- Keep access and refresh tokens in Android-backed secure storage. The client restores them at launch, shares one refresh attempt across concurrent requests, and clears rejected sessions.
- Do not embed production secrets through `--dart-define`.
- Use Android App Links or verified deep links in production.
- Redact sensitive content from screenshots and push notifications.
- Consider Play Integrity signals as risk input, not authentication.
- Offline group and financial history is stored in app-private SQLite storage on
  supported native platforms. It is not encrypted at the application layer;
  treat it as sensitive, and assess database encryption and backup exclusions
  before public deployment. Offline sync is opt-in per account and requires
  authenticated API access.

## Privacy

Collect only data needed for group expenses and payment reconciliation. The
[privacy, retention, and deletion specification](PRIVACY.md) records the data
inventory, target schedules, account-anonymization behavior, ARCO/support
runbook, backup tombstones, legal baseline, and unresolved release blockers.
The [Spanish](PRIVACY_NOTICE_ES.md) and
[English](PRIVACY_NOTICE_EN.md) user-facing notices remain pre-release drafts
until the controller identity, address, privacy channel, processors, and legal
approval are recorded.

Do not invite external beta users, enable salary collection, or add a new data
purpose until the applicable privacy blocker is closed and the notice shown at
collection matches deployed behavior.
