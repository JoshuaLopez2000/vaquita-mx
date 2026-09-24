# Security baseline

This application handles financial metadata even though it does not hold funds. Treat group membership, expense descriptions, balances, phone numbers, and provider identifiers as sensitive.

## Required before public deployment

- TLS only; redirect or reject plaintext traffic.
- Authentication and authorization on every user or group resource.
- Password hashing with Argon2id when passwords are supported.
- Short-lived access tokens, rotated refresh tokens, and server-side revocation.
- Rate limits on authentication, invitations, and payment operations.
- Encrypted secrets supplied by the hosting platform, never the mobile app.
- Database encryption at rest and encrypted backups.
- Structured audit events without bank data, tokens, or secrets in logs.
- Dependency, static-analysis, and container scanning in CI.

## Payment controls

- Generate provider calls only from the server.
- Verify callback signatures before parsing business fields.
- Store each provider event ID under a unique database constraint.
- Process events transactionally and make retries safe.
- Match amount, currency, receiver, and correlation ID before settlement.
- Never accept a client-side `paid: true` value as proof of payment.
- Use compensating ledger entries instead of destructive edits.

## Mobile controls

- Keep access tokens in Android-backed secure storage.
- Do not embed production secrets through `--dart-define`.
- Use Android App Links or verified deep links in production.
- Redact sensitive content from screenshots and push notifications.
- Consider Play Integrity signals as risk input, not authentication.

## Privacy

Collect only data needed for group expenses and payment reconciliation. Define retention and deletion policies, publish a privacy notice, and assess applicable Mexican privacy requirements before a real launch.
