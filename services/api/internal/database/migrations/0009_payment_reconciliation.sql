-- Payment reconciliation reuses the provider adapter to confirm pending
-- requests, replay-safe from check to settlement.

-- The provider-side reference returned by CreateRequest. Lookup is keyed by
-- this value; the internal request id stays the mobile-facing identifier.
ALTER TABLE payment_requests
  ADD COLUMN provider_ref TEXT NOT NULL DEFAULT '';

-- Bounded retry bookkeeping. reconcile_after doubles as the claim lease while
-- a worker processes the row; NULL parks the request for manual review after
-- the maximum number of attempts.
ALTER TABLE payment_requests
  ADD COLUMN reconcile_attempts INTEGER NOT NULL DEFAULT 0;
ALTER TABLE payment_requests
  ADD COLUMN reconcile_after TIMESTAMPTZ NOT NULL DEFAULT now() + interval '5 minutes';
CREATE INDEX payment_requests_reconcile_idx
  ON payment_requests(status, reconcile_after);

-- Immutable audit trail of reconciliation outcomes distinct from provider
-- callbacks. Mismatches and manual-review outcomes live here.
CREATE TABLE payment_reconcile_events (
  id TEXT PRIMARY KEY,
  payment_request_id TEXT NOT NULL REFERENCES payment_requests(id),
  provider TEXT NOT NULL,
  outcome TEXT NOT NULL CHECK (outcome IN ('PAID', 'TERMINAL', 'MISMATCH', 'RETRY', 'MANUAL')),
  detail TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
