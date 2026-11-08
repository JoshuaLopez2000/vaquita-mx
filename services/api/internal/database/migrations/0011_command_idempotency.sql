CREATE TABLE command_idempotency (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  operation TEXT NOT NULL,
  scope_id TEXT NOT NULL DEFAULT '',
  idempotency_key TEXT NOT NULL,
  payload_hash TEXT NOT NULL,
  status_code SMALLINT NOT NULL,
  response_body JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, operation, scope_id, idempotency_key)
);

CREATE INDEX command_idempotency_created_idx ON command_idempotency(created_at);
