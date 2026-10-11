CREATE TABLE payment_requests (
  id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL REFERENCES expense_groups(id),
  creditor_member_id TEXT NOT NULL REFERENCES members(id),
  debtor_member_id TEXT NOT NULL REFERENCES members(id),
  requester_user_id TEXT NOT NULL REFERENCES users(id),
  amount_cents BIGINT NOT NULL CHECK (amount_cents > 0),
  currency CHAR(3) NOT NULL CHECK (currency = 'MXN'),
  provider TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('PENDING', 'PAID', 'EXPIRED', 'FAILED')),
  payment_url TEXT NOT NULL,
  correlation_id TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  idempotency_key TEXT NOT NULL,
  payload_hash TEXT NOT NULL,
  settlement_id TEXT UNIQUE REFERENCES settlements(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  paid_at TIMESTAMPTZ,
  UNIQUE(requester_user_id, idempotency_key)
);

CREATE INDEX payment_requests_group_idx ON payment_requests(group_id, created_at DESC);
CREATE INDEX payment_requests_debtor_idx ON payment_requests(debtor_member_id, status);

CREATE TABLE payment_provider_events (
  id TEXT PRIMARY KEY,
  provider TEXT NOT NULL,
  provider_event_id TEXT NOT NULL,
  payment_request_id TEXT NOT NULL REFERENCES payment_requests(id),
  status TEXT NOT NULL CHECK (status IN ('PENDING', 'PAID', 'EXPIRED', 'FAILED')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(provider, provider_event_id)
);
