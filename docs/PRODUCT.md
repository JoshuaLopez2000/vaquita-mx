# Product definition

## Problem

Groups routinely share restaurant bills, trips, rent, subscriptions, and gifts. Chat messages and bank-transfer screenshots make it difficult to determine who paid, who owes money, and whether a settlement belongs to the correct expense.

Vaquita MX gives the group one ledger and gives each debtor a clear payment request.

## Primary users

- Friends sharing travel and entertainment expenses.
- Roommates sharing recurring household costs.
- Families organizing purchases and events.
- Small informal groups that need transparent reimbursement, not merchant checkout.

## Core flow

1. A user opens the app and can create and manage groups without an account.
2. The app stores local groups, expenses, and settlements on the device.
3. A user can log in or sign up from Profile and choose whether to sync local
   groups now or later.
4. Invites are sent only when the user opts in to syncing. Sync merges local
   groups with the account's existing groups and safely retries pending changes.
5. A member records an expense and its payer or payers.
6. The group chooses equal, percentage, shares, or exact splits.
7. The server calculates obligations in integer centavos.
8. In a shared group, a creditor can request payment or record that they
   received all or part of the outstanding amount. A debtor cannot manually
   confirm receipt on the creditor's behalf.
9. The debtor opens a request and completes payment externally; a verified
   provider event, or the explicitly simulated demo, may record settlement.
10. In a personal group, its owner controls full or partial bilateral
    settlements. Local groups offer the same ledger control on-device.
11. The balance view changes while the original expense remains immutable.

Offline data remains on the device until the user explicitly enables sync for
the signed-in account. Once enabled, pending changes retry when connectivity
returns. The app uses SQLite on supported native platforms; web currently keeps
offline data in memory only.

Without signing in, groups are personal and local-only. Payment requests,
shared-group invitations, and other server-dependent actions are unavailable.
Recording a local settlement changes only the group's ledger; it never
represents or initiates a real transfer.

## MVP scope

- Account creation and authentication.
- Groups, invite links, membership, and roles.
- Expenses with one or multiple payers.
- Four split methods.
- Per-member balances.
- Individual payment requests and expiration.
- Partial and full settlements.
- Reminders and a simple activity feed.
- Spanish-first UI with English localization support.
- Simulated provider that supports deterministic demos.
- Offline-first group and ledger management with opt-in account sync.

## Deliberate exclusions

- Holding customer funds.
- Collecting bank credentials.
- Initiating payments on behalf of a user without an authorized participant.
- Multi-currency accounting in the first release.
- Lending, credit scoring, or charging collection fees.

## Success indicators

- A new group can record and split an expense in under two minutes.
- Every centavo is allocated; split rounding never changes the expense total.
- Repeated provider callbacks never duplicate a settlement.
- The demo can run from a public Android build against a remote API.

## CV framing

> Built an Android-first group-expense platform with immutable financial records, exact monetary allocation, idempotent payment processing, and a provider abstraction designed for Banco de Mexico's certified CoDi collection workflow.
