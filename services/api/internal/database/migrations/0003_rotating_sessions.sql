CREATE TABLE session_families (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX session_families_user_idx ON session_families(user_id);

ALTER TABLE sessions
  ADD COLUMN family_id TEXT REFERENCES session_families(id) ON DELETE CASCADE;
ALTER TABLE sessions
  ADD COLUMN revoked_at TIMESTAMPTZ;

-- Legacy 30-day bearer sessions remain valid only for a bounded transition.
UPDATE sessions
SET expires_at = LEAST(expires_at, now() + interval '15 minutes')
WHERE family_id IS NULL AND revoked_at IS NULL;

CREATE INDEX sessions_family_idx ON sessions(family_id);

CREATE TABLE refresh_tokens (
  token_hash TEXT PRIMARY KEY,
  family_id TEXT NOT NULL REFERENCES session_families(id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ,
  replaced_by_hash TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX refresh_tokens_family_idx ON refresh_tokens(family_id);
