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

1. A user creates a group and invites members.
2. A member records an expense and its payer or payers.
3. The group chooses equal, percentage, shares, or exact splits.
4. The server calculates obligations in integer centavos.
5. A creditor creates one request per debtor.
6. The debtor opens the request and completes payment externally.
7. An authenticated provider event, or the demo simulator, records settlement.
8. The balance view changes while the original expense remains immutable.

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
