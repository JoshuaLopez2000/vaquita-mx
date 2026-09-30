# API reference

All domain routes are prefixed with `/api/v1` and use JSON. Send an opaque
session token after registration or login as `Authorization: Bearer <token>`.

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/auth/register` | Create an account and session. |
| `POST` | `/auth/login` | Create a session for an existing account. |
| `GET` | `/groups` | List groups visible to the signed-in user. |
| `POST` | `/groups` | Create a group. |
| `PATCH` | `/groups/{groupID}` | Change owner-only group settings. |
| `POST` | `/groups/{groupID}/members` | Invite a member; owner only. |
| `PATCH` | `/groups/{groupID}/members/{memberID}` | Edit owner-managed identity data or the authenticated member's own salary consent. |
| `DELETE` | `/groups/{groupID}/members/{memberID}` | Remove a non-owner member; owner only. |
| `POST` | `/groups/{groupID}/expenses` | Record an equal or salary-weighted expense. |
| `POST` | `/groups/{groupID}/settlements` | Record a **simulated** settlement for the current user. |
| `GET` | `/groups/{groupID}/unpaid` | Load projected group balances. |
| `GET` | `/group-invitations` | List the authenticated user's pending invitations. |
| `POST` | `/group-invitations/{groupID}/response` | Accept or decline the authenticated user's pending invitation. |
| `POST` | `/payment-requests` | Create a **simulated** request for an exact share of an expense paid by the authenticated user. |

Every member object returned in a group or invitation includes a persisted
`role` of `owner` or `member`. See the authorization matrix in
[`SECURITY.md`](SECURITY.md#group-authorization-matrix) for the permissions and
membership-state requirements applied to these routes.

`POST /payment-requests` is intentionally not a real payment operation. It
requires a valid session, group access, an expense paid by that user, an active
participant debtor, and the exact centavo share computed by the ledger. The
returned deep link is a simulator artifact and does not settle a balance.

Errors use JSON with an `error` string. The current demo uses `401` for a
missing or invalid session, `404` when a group or resource is not visible to
the user, and `422` for invalid financial input.
