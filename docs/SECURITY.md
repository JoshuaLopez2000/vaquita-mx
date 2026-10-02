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
| Record a settlement | Own accepted membership only | Own accepted membership only | Deny |
| Accept or decline an invitation | Not applicable | Pending invitee only | Removed or declined: deny |

The owner role cannot be removed. Payment requests must match the exact
MXN-centavo amount in the server-derived creditor/debtor relation for active,
accepted members. Settlement commands may only settle the authenticated
member's relationship with another member.

## Mobile controls

- Keep access and refresh tokens in Android-backed secure storage. The client restores them at launch, shares one refresh attempt across concurrent requests, and clears rejected sessions.
- Do not embed production secrets through `--dart-define`.
- Use Android App Links or verified deep links in production.
- Redact sensitive content from screenshots and push notifications.
- Consider Play Integrity signals as risk input, not authentication.

## Privacy

Collect only data needed for group expenses and payment reconciliation. Define retention and deletion policies, publish a privacy notice, and assess applicable Mexican privacy requirements before a real launch.
