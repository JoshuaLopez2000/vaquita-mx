ALTER TABLE payment_requests
  ADD COLUMN IF NOT EXISTS description TEXT NOT NULL DEFAULT '';

CREATE INDEX IF NOT EXISTS payment_requests_created_idx
  ON payment_requests(created_at DESC, id DESC);
