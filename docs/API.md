# API reference

All domain routes are prefixed with `/api/v1` and use JSON. Send an opaque
session token after registration or login as `Authorization: Bearer <token>`.

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/auth/register` | Create an account and session. |
| `POST` | `/auth/login` | Create a session for an existing account. |
| `POST` | `/auth/refresh` | Rotate a one-time refresh token and return a new session. |
| `POST` | `/auth/sign-out` | Revoke the authenticated device session. |
| `POST` | `/auth/sign-out-all` | Revoke every session for the authenticated user. |
| `GET` | `/groups` | List groups visible to the signed-in user. |
| `POST` | `/groups` | Create a group. |
| `PATCH` | `/groups/{groupID}` | Change owner-only group settings. |
| `POST` | `/groups/{groupID}/members` | Invite a member; owner only. |
| `PATCH` | `/groups/{groupID}/members/{memberID}` | Edit owner-managed identity data or the authenticated member's own salary consent. |
| `DELETE` | `/groups/{groupID}/members/{memberID}` | Remove a non-owner member; owner only. |
| `POST` | `/groups/{groupID}/expenses` | Record an equal, salary-weighted, or exact-split expense, with one or more payers. |
| `POST` | `/groups/{groupID}/settlements` | Record a **simulated** settlement for the current user. |
| `GET` | `/groups/{groupID}/unpaid` | Load projected group balances. |
| `GET` | `/group-invitations` | List the authenticated user's pending invitations. |
| `POST` | `/group-invitations/{groupID}/response` | Accept or decline the authenticated user's pending invitation. |
| `POST` | `/payment-requests` | Create a durable **simulated** request for an exact share of an expense paid by the authenticated user. |
| `POST` | `/payment-requests/{requestID}/simulate` | Confirm a simulator event as the debtor; this is not a real transfer. |

Every member object returned in a group or invitation includes a persisted
`role` of `owner` or `member`. See the authorization matrix in
[`SECURITY.md`](SECURITY.md#group-authorization-matrix) for the permissions and
membership-state requirements applied to these routes.

Expense creation accepts ordered `payers`, each with `member_id` and positive
integer `amount_cents`. Their total must be at least `amount_cents`, and all
payers must be active group members. `split_overpayment` defaults to `true`:
when it is true, money paid above the entered total is included in the group
balances. When it is false, every payer contribution must be supplied and the
excess is retained by those payers proportionally to their contributions. It
does not create debt, and is stored as immutable retained-overpayment data for
future financial statistics. The legacy `payer_id` remains readable for
historical single-payer expenses; new clients should send and display `payers`.
Group responses expose `paid_amount_cents`, `overpayment_cents`,
`split_overpayment`, and (when retained) ordered `retained_overpayments` so
clients can report distributed and retained excess separately.

For `split_mode: "exact"`, creation also requires ordered `shares`, each with
`member_id` and non-negative integer `amount_cents`. A share is that
participant's consumption, separate from a payer contribution. Each active
participant must occur exactly once, and all shares must allocate every
centavo of the entered expense total. The server rejects duplicate,
missing, inactive, negative, under-allocated, and over-allocated shares.

`POST /payment-requests` is intentionally not a real payment operation. It
requires a valid session, group access, an expense paid by that user, an active
participant debtor, and the exact centavo share computed by the ledger. The
returned deep link is a simulator artifact and does not settle a balance. It
also requires an `Idempotency-Key` header (1–128 characters). A retry with the
same authenticated user, key, and payload returns the original request; a key
reused with another payload returns `409 idempotency_key_conflict`.

The debtor confirms a demo through `POST /payment-requests/{requestID}/simulate`
with `{ "provider_event_id": "opaque-demo-event" }`. A provider event ID is
unique per provider: callbacks may be retried safely and create at most one
immutable settlement. This route is authenticated, accepts no claim that money
moved, and is only the deterministic simulator boundary.

## Correlation IDs and errors

Every response includes `X-Correlation-ID`. A caller may send that header with
1 to 64 ASCII letters, digits, hyphens, underscores, periods, or colons. The
API echoes a valid value; otherwise it generates a new opaque ID. Include the
response ID when reporting a failed request. Logs contain the same ID but do
not contain authorization tokens, phone numbers, request bodies, or financial
descriptions.

Failures use this version 1 envelope:

```json
{
  "version": "1",
  "code": "validation_failed",
  "message": "invalid group settings",
  "fields": {
    "name": "required"
  },
  "error": "invalid group settings"
}
```

`code` is the stable value clients branch on. `message` is safe for display but
may be reworded or localized. `fields` is optional and its values are stable
machine-readable reasons. The deprecated `error` string mirrors `message` for
one beta-version compatibility window; new clients must not branch on it.

| Code | Typical status | Meaning |
| --- | --- | --- |
| `invalid_json` | 400 | The JSON body is malformed, too large, or contains unsupported fields. |
| `request_limit_exceeded` | 400 | A bounded collection exceeds its allowed size. |
| `authentication_required` | 401 | The access token is missing, invalid, expired, or revoked. |
| `invalid_credentials` | 401 | Login credentials were rejected. |
| `invalid_refresh_token` | 401 | A refresh token is invalid, expired, reused, or revoked. |
| `resource_not_found` | 404 | The resource is missing or intentionally hidden from this user. |
| `email_already_registered` | 409 | Registration conflicts with an existing account. |
| `idempotency_key_required` | 400 | A payment-request creation is missing a valid `Idempotency-Key`. |
| `idempotency_key_conflict` | 409 | The key was already used by this user for a different request payload. |
| `validation_failed` | 422 | Domain or financial input is invalid. |
| `internal_error` | 500 | An unexpected server failure occurred; details are logged only server-side. |
| `service_unavailable` | 503 | A required service is temporarily unavailable. |

Hidden and missing resources deliberately return the same status, code, and
safe message so authorization checks do not reveal their existence.

Registration, login, and refresh return `access_token`, `refresh_token`,
`access_expires_at`, `refresh_expires_at`, and `user`. Access tokens expire
after 15 minutes. Refresh tokens belong to a 30-day device-session family and
are replaced every time they are used. Reusing a consumed refresh token revokes
the whole family. The deprecated `token` response field mirrors
`access_token` during the bounded legacy-client transition.
