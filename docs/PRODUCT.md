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
6. The group chooses equal, percentage, salary, or exact splits (shares ratio
   splitting is tracked separately). Percentage splits use integer basis points
   (2-decimal fixed point, `10000` = `100.00%`, each participant strictly
   positive) with deterministic largest-remainder centavo allocation breaking
   ties in stored participant order.
7. The server calculates obligations in integer centavos and persists final
   shares for exact and percentage splits so stored centavos drive balances.
8. In a shared group, a creditor can request payment or record that they
   received all or part of the outstanding amount. A debtor cannot manually
   confirm receipt on the creditor's behalf.
9. Pending and historical payment requests surface in the Bandeja (`Inbox`) tab
   (filterable by `All`, `To pay`, and `Sent`) and inside shared group details.
   Creditors can check status and share the `vaquitamx://payment-requests/{id}`
   deep link; debtors can open a request directly or from the app and complete
   it through the explicitly labeled simulated demo (or a verified provider
   event in future live integrations). Paid, expired, and failed requests
   clearly explain their state and disallow completion.
10. In a personal group, its owner controls full or partial bilateral
    settlements. Local groups offer the same ledger control on-device.
11. The balance view changes while the original expense remains immutable.
12. To correct a posted expense or settlement, an authorized member records an
    immutable compensating reversal with a required reason and may post a
    separate replacement record linked to the reversed entry. Reversed records
    remain visible and clearly marked in group and movement history alongside
    their compensating reversals.

Local-only data remains on the device until the user explicitly enables sync
for the signed-in account. On sign-in, server-backed groups are fetched and
cached locally in SQLite so they remain usable offline and across restarts.
Expenses, personal-group manual settlements, shared-group received-payment
confirmations, and compensating reversals of already-synced records on
server-backed groups use the authenticated API when online;
when the device is offline or a transient transport failure occurs, they are
saved optimistically on-device and queued in a durable outbox that replays
automatically with stable idempotency keys when connectivity returns. Pending
offline expenses or settlements on a server-backed group must sync before they
can be reversed. Payment
requests require an active internet connection and are disabled offline.
Permanent server rejections surface visibly so the user can retry or discard
the failed entry. Once local sync is enabled, pending local-only group changes
also retry when connectivity returns. The app uses SQLite on supported native
platforms; web currently keeps offline data and queued mutations in memory
only. Group lists and group details label each group as local or server-backed
and show pending offline sync counts.

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
