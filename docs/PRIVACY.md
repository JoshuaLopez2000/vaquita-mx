# Privacy, retention, and deletion specification

Status: **pre-release draft**  
Last reviewed: 2026-09-30  
Applies to: Vaquita MX private beta

This document records the product's current data flows and the target privacy
behavior for the private beta. It is an engineering and operations control,
not legal advice or a claim of compliance. Items marked **release blocker**
must be resolved before inviting external beta users.

The user-facing drafts are:

- [Spanish privacy notice](PRIVACY_NOTICE_ES.md) — controlling product copy.
- [English privacy notice](PRIVACY_NOTICE_EN.md) — convenience translation.

## Roles and scope

The legal person operating the beta is the data controller (`responsable`).
Its identity, physical address, privacy contact, and selected infrastructure
processors are not yet recorded. Those omissions are release blockers and are
shown as placeholders in both notices.

The current product:

- manages group-expense metadata in MXN;
- does not hold funds or collect bank credentials;
- uses a simulated payment provider and must not imply a real transfer;
- has no advertising, marketing, third-party analytics, crash-reporting SDK,
  or live payment provider in the repository;
- reads Android contacts only after the operating-system permission prompt and
  sends only contacts the user selects for saving; and
- exposes a contact-matching API, although the current mobile screen does not
  invoke matching automatically.

Before adding analytics, notifications, attachments, a live payment provider,
or another new purpose, update the inventory and notices and obtain any newly
required consent.

## Data inventory and target retention

`Current behavior` describes the repository at the review date. `Target` is a
release requirement and must not be represented to users as implemented until
the referenced control exists and has been tested.

| Data | Source and storage | Purpose and sensitivity | Current behavior | Target retention and deletion |
| --- | --- | --- | --- | --- |
| Account name, email, and Mexican phone number | User; PostgreSQL `users`; encrypted mobile storage contains a session copy | Account identity, login, invitations, contact matching; personal identifiers | Retained without expiry; email and phone are unique | Keep while the account is active. On an approved deletion, remove phone/email from active use and replace identity fields with non-identifying tombstone values within the ARCO execution period, subject to blocking or legal hold. |
| Password | User; only a bcrypt hash is stored in `users` | Authentication; secret credential | Hash retained with account | Replace with a random unusable hash when deletion is executed. Never retain or log plaintext. |
| Monthly salary and salary-sharing consent | User; `users.salary_cents`, `group_members.salary_sharing`; session copy on device | Optional salary-weighted splits; financial/patrimonial data requiring explicit-consent review | Exact salary is returned only to the account holder, but historical shares are recalculated from the current salary | Keep only while needed for enabled salary splitting. On revocation/deletion, disable consent and erase the exact salary after immutable expense shares have been snapshotted. Snapshot support is a release blocker because erasing the current field would presently change history. |
| Access/refresh session metadata | Random tokens on device; hashes, family IDs, expiry, use, replacement, and revocation timestamps in PostgreSQL | Authentication and security audit | Access tokens last 15 minutes; refresh families last up to 30 days; expired/revoked rows have no cleanup job | Revoke immediately on deletion. Purge access, refresh, and family rows no later than 30 days after expiry/revocation unless a documented security incident requires a short legal hold. |
| Mobile authentication copy and last login email | User/API; Android-backed secure storage | Restore session and prefill login | Sign-out clears tokens and session user, but not `last_login_email` | Clear all four values on account deletion. Offer a local “forget email” control. Device copies are also removed by app-data deletion/uninstall subject to OS behavior. |
| Selected address-book names and phone numbers | User's Android contacts; transient app memory; selected entries persisted in PostgreSQL `contacts` | User-managed contact list and invitations | Android reads the address book after runtime permission; only selected contacts are saved; individual server contacts can be deleted | Do not upload unselected entries. Delete an individual contact immediately on request and from the live database within 15 business days at the latest. Delete all contacts when the owner's deletion is executed. Backup copies expire with the backup schedule. |
| Contact-match phone batch | Authenticated request to `/contacts/matches`; processed against `users.phone` | Find existing users | Request body is not intentionally logged or persisted by application code; endpoint accepts at most 500 numbers | Keep only in request memory. Do not add body logging, analytics, or cache persistence. Treat ingress/provider logs as a processor review item. |
| Group and member profile data | User/group owner; `expense_groups`, `members`, `group_members` | Membership, roles, invitations, authorization, display | Names and phones may be copied into member records; removed/declined state is retained | Keep while the group ledger is active. On account deletion, unlink the user and pseudonymize display name/phone while preserving a stable member ID and role/history required by other members. Transfer ownership or archive the group before deletion. |
| Expenses and participant relationships | Group member; `expenses`, `expense_participants` | Immutable shared ledger, balance calculation, disputes | Description, amount, payer, participants, split mode, and timestamp are retained without expiry | Keep while any authorized group participant uses the ledger, then block for the legally approved limitation period. Afterwards delete the closed ledger or irreversibly disassociate it. During an individual deletion, retain required shared ledger facts under a pseudonymous member ID; suppress unnecessary personal text through a non-destructive redaction layer. |
| Settlements | Group member; `settlements` | Separate immutable simulated-settlement history and balances | Retained without expiry | Same lifecycle as the shared ledger. Preserve amount, direction, timestamp, and pseudonymous member references; never describe simulator entries as real transfers. |
| Simulated payment requests | Request input and in-memory provider result | Demonstration of a payment-request flow | Not persisted; random request ID and deep link expire after 24 hours in the response | Keep only in memory for the request. Revisit this row when #4 introduces durable requests and events. |
| API logs | Application standard output; future hosting log service | Operations, security, troubleshooting | Request method, path, and duration are logged; errors may contain internal operation errors; bodies and authorization headers are not intentionally logged | Default retention: 30 days. Security-incident extracts: up to 90 days or documented legal hold. Redact tokens, phone numbers, emails, salary, descriptions, request bodies, and payment payloads. Review whether paths contain identifiers before deployment. |
| Support and ARCO case records | Privacy contact and restricted case register, not implemented | Authenticate and evidence privacy requests | No production channel or register exists | Keep case metadata and outcome for 24 months after closure; delete identity-document copies within 30 days after verification/closure unless legally required. Restrict access to the designated privacy owner. |
| PostgreSQL backups | Future managed database backup service | Disaster recovery | Deployment guidance requires encrypted backups but does not select a provider or expiry | Use encrypted rolling backups with a maximum 35-day lifetime. Prevent ordinary access, record restores, and reapply deletion tombstones immediately after any restore. No selective mutation of immutable backup snapshots. |

Retention timers pause only for a documented legal hold, active dispute, security
investigation, or another legally reviewed obligation. The privacy owner must
record the reason, scope, approver, and review/expiry date. “Keep forever” is
not an acceptable default.

## Consent and contact import

### Salary data

Salary is financial/patrimonial information. Before collecting it, the app must
show the integral or linked simplified notice and capture an affirmative,
auditable action separate from accepting unrelated optional purposes. Refusing
or revoking salary use must leave equal splitting available. Group members must
continue to see the existing warning that proportional results can reveal
relative salary differences.

### Address-book data

The import flow must:

1. explain before the Android prompt that access is optional and is used to let
   the user select contacts for Vaquita;
2. work without contact permission through manual entry;
3. keep the device list in memory only and upload only selected entries;
4. state that selected names and phone numbers will be stored on the server and
   may correspond to people who do not use Vaquita;
5. let the uploader delete each saved contact and all saved contacts; and
6. require the uploader to confirm they are authorized to provide the selected
   details, while the legal review defines the indirect-notice mechanism for
   non-users.

Permission denial must not degrade unrelated account or ledger features.

## Account deletion and anonymization decision

Account deletion is an authenticated privacy workflow, not `DELETE FROM users`.
The current foreign keys and immutable-ledger rules require a staged process.

| Record | Action after an approved deletion | Reason |
| --- | --- | --- |
| Active and refresh sessions | Revoke immediately, then purge on schedule | End account access and reduce credential risk. |
| Saved contacts | Delete from the live database | They belong to the deleting user's private contact list. |
| Email, phone, name, password hash | Replace with unique tombstone values and an unusable credential | Remove direct identifiers without breaking referenced ledger rows. |
| Exact salary and salary consent | Set consent false and salary to zero only after historical split inputs are immutable | Avoid retaining unnecessary patrimonial data or changing past balances. |
| User/member links | Remove the login link; retain a stable pseudonymous member record | Other members still need an intelligible, balanced ledger. |
| Owned groups | Transfer to an eligible accepted member with confirmation, or archive read-only | Avoid orphaning or destructively deleting shared history. |
| Expenses and settlements | Preserve immutable amounts and relationships under pseudonymous IDs; apply a display-redaction overlay where justified | Protect other participants' rights and ledger integrity without exposing the deleted identity. |
| Support/audit proof | Block and restrict to the approved retention window | Demonstrate request handling without continuing product use. |
| Backups | Record a deletion tombstone and let encrypted backups expire; reapply after restoration | Backup mutation is unreliable and can damage recovery integrity. |
| Mobile secure storage | Clear tokens, session user, and remembered email | Remove the local account copy from the device under app control. |

The implementation must be transactional and idempotent, produce an audit
event without copying the deleted data, and never mutate an expense or
settlement amount. A failed step leaves the account blocked from login and the
case queued for retry rather than partially reactivating it.

## ARCO and privacy-support runbook

This runbook applies to access, rectification, cancellation, opposition,
consent revocation, use limitation, and account deletion requests.

1. **Receive.** Accept through the designated privacy email and, once built,
   the authenticated in-app channel. Record a case ID, received time, requested
   right, reply channel, and deadline. Do not place request details in general
   application logs.
2. **Acknowledge.** Send the case ID and explain identity verification. Never
   disclose whether an account exists to an unverified requester.
3. **Verify proportionately.** Prefer an authenticated session or a challenge
   to the registered email/phone. Request government identification only when
   necessary; store it separately and delete it on the schedule above.
4. **Discover.** Search the account, contacts, membership records, ledgers,
   session history, logs, support records, and processors. Identify data about
   the requester that another user supplied as a contact/member.
5. **Protect third parties.** Export or correct only the requester's data.
   Redact other members' identifiers and secrets. Determine whether cancellation
   requires blocking or partial denial to protect another participant's rights.
6. **Decide.** Communicate the determination within **20 business days** of
   receipt. If approved, execute it within the following **15 business days**.
   A one-time equal extension requires documented circumstances and notice.
7. **Execute.** Use an idempotent runbook/tool. Revoke access first, apply live
   deletion or pseudonymization, create backup tombstones, and notify relevant
   processors. Do not directly edit financial rows.
8. **Respond.** Describe completed actions, blocked records and their reason,
   expected backup expiry, any partial denial and evidence, and the route for
   further review. Use the same channel as the request unless a safer verified
   channel was agreed.
9. **Close and review.** Record outcome and timestamps without unnecessary
   copies of the underlying data. Review overdue cases and deletion retries at
   least weekly during the beta.

Requests are free except legally permitted reproduction or delivery costs. The
privacy owner must be a named person or department before launch.

## Backup deletion and restoration

- Configure a maximum 35-day rolling retention and encryption at rest.
- Limit restore access to named operators and record every restore.
- Keep a deletion-tombstone register outside the restored database. It contains
  only the stable internal subject ID, request ID, execution time, and state.
- After a restore, block external traffic, replay every unexpired tombstone,
  verify that direct identifiers and sessions remain removed, then reopen.
- A restored backup must never silently reactivate an account or contact.
- Backup expiry is not a substitute for deleting live data.

## Synthetic deletion rehearsal

Before private-beta release and after material schema changes:

1. Create two synthetic users, a shared group, selected saved contacts, salary
   consent, expenses, a simulated settlement, and two device sessions.
2. Record direct database counts and exact balances.
3. Submit a synthetic deletion request through the support runbook.
4. Verify all sessions fail, private contacts are gone, direct identifiers are
   tombstoned, and the exact salary is removed only after share snapshots exist.
5. Verify the remaining user can read an exactly balanced, pseudonymized ledger
   and no financial row was updated or deleted.
6. Restore a synthetic pre-deletion backup in isolation and replay the
   tombstone; verify the account does not reappear.
7. Save only the case ID, checks, timestamps, counts, and pass/fail result as
   evidence. Never use real contacts or financial data.

The rehearsal cannot pass until deletion automation and immutable salary-share
storage exist.

## Legal baseline reviewed

Reviewed 2026-09-30 against primary official sources:

- [Federal Law on Protection of Personal Data Held by Private Parties — current text, last reform 2025-11-14](https://www.diputados.gob.mx/LeyesBiblio/pdf/LFPDPPP.pdf)
- [Chamber of Deputies federal-law index](https://www.diputados.gob.mx/LeyesBiblio/index.htm)
- [Official privacy-notice guidelines](https://sidof.segob.gob.mx/notas/docFuente/5284966)

The review maps the current design to these requirements:

- principles of lawfulness, purpose, loyalty, consent, quality,
  proportionality, information, and accountability (article 5);
- express consent for financial or patrimonial data (article 7);
- deletion after purpose and retention end, with blocking where applicable
  (article 10);
- mandatory notice content and electronic delivery (articles 14–17);
- administrative, technical, and physical safeguards plus significant-breach
  notice (articles 18–20);
- access, rectification, cancellation, and opposition, including blocking and
  third-party rights (articles 21–26);
- a designated privacy owner and the 20/15-business-day response/execution
  periods (articles 27–34); and
- controls for national or international transfers (articles 35–36).

The 2025 law names the Secretaría Anticorrupción y Buen Gobierno as the federal
authority. This recorded review does not replace advice from qualified Mexican
privacy counsel.

## Release blockers and owners

| Blocker | Required owner |
| --- | --- |
| Fill controller legal name, physical address, privacy email, and privacy owner in both notices | Product/legal |
| Approve legal basis, salary classification/consent wording, indirect contact notice, blocking periods, and treatment of minors | Qualified Mexican privacy counsel |
| Select hosting/log/backup/support processors, regions, contracts, transfer basis, and exact retention controls | Infrastructure/legal/security |
| Persist immutable per-expense shares before exact salary can be erased safely | API |
| Build an idempotent deletion/anonymization command, tombstone replay, export, and integration tests | API/security |
| Clear `last_login_email` and all session data during deletion; expose the integral notice before registration | Mobile |
| Add pre-permission contact explanation, explicit selected-contact upload confirmation, and delete-all control | Mobile/product |
| Configure 30-day logs, 35-day backups, restricted ARCO register, and a restore rehearsal | Infrastructure/privacy owner |
| Complete and record legal, security, product, and operations approval | Named reviewers |

If deployed behavior differs from the notices or this inventory, pause the
affected collection until the implementation and notices agree.
