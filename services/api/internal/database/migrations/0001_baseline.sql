CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL CHECK (length(trim(name)) > 1),
  email TEXT NOT NULL UNIQUE,
  phone TEXT UNIQUE,
  password_hash TEXT NOT NULL,
  salary_cents BIGINT NOT NULL DEFAULT 0 CHECK (salary_cents >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS salary_cents BIGINT NOT NULL DEFAULT 0;
CREATE UNIQUE INDEX IF NOT EXISTS users_phone_unique_idx ON users(phone) WHERE phone IS NOT NULL;

CREATE TABLE IF NOT EXISTS contacts (
  id TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  phone TEXT NOT NULL,
  linked_user_id TEXT REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(owner_id, phone)
);

CREATE TABLE IF NOT EXISTS sessions (
  token_hash TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS sessions_user_idx ON sessions(user_id);

CREATE TABLE IF NOT EXISTS members (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  phone TEXT,
  user_id TEXT REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE members ADD COLUMN IF NOT EXISTS phone TEXT;
ALTER TABLE members ADD COLUMN IF NOT EXISTS user_id TEXT REFERENCES users(id);

CREATE TABLE IF NOT EXISTS expense_groups (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  emoji TEXT NOT NULL,
  owner_id TEXT REFERENCES users(id),
  visibility TEXT NOT NULL DEFAULT 'personal',
  salary_split_enabled BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE expense_groups ADD COLUMN IF NOT EXISTS owner_id TEXT REFERENCES users(id);
ALTER TABLE expense_groups ADD COLUMN IF NOT EXISTS visibility TEXT NOT NULL DEFAULT 'personal';
ALTER TABLE expense_groups ADD COLUMN IF NOT EXISTS salary_split_enabled BOOLEAN NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS group_members (
  group_id TEXT NOT NULL REFERENCES expense_groups(id) ON DELETE CASCADE,
  member_id TEXT NOT NULL REFERENCES members(id),
  position INTEGER NOT NULL,
  user_id TEXT REFERENCES users(id),
  removed_at TIMESTAMPTZ,
  salary_sharing BOOLEAN NOT NULL DEFAULT false,
  accepted BOOLEAN NOT NULL DEFAULT true,
  declined_at TIMESTAMPTZ,
  PRIMARY KEY(group_id, member_id)
);
ALTER TABLE group_members ADD COLUMN IF NOT EXISTS user_id TEXT REFERENCES users(id);
ALTER TABLE group_members ADD COLUMN IF NOT EXISTS removed_at TIMESTAMPTZ;
ALTER TABLE group_members ADD COLUMN IF NOT EXISTS salary_sharing BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE group_members ADD COLUMN IF NOT EXISTS accepted BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE group_members ADD COLUMN IF NOT EXISTS declined_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS expenses (
  id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL REFERENCES expense_groups(id) ON DELETE CASCADE,
  description TEXT NOT NULL,
  amount_cents BIGINT NOT NULL,
  payer_id TEXT NOT NULL REFERENCES members(id),
  split_mode TEXT NOT NULL DEFAULT 'equal',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE expenses ADD COLUMN IF NOT EXISTS split_mode TEXT NOT NULL DEFAULT 'equal';

CREATE TABLE IF NOT EXISTS expense_participants (
  expense_id TEXT NOT NULL REFERENCES expenses(id) ON DELETE CASCADE,
  member_id TEXT NOT NULL REFERENCES members(id),
  position INTEGER NOT NULL,
  PRIMARY KEY(expense_id, member_id)
);

CREATE TABLE IF NOT EXISTS settlements (
  id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL REFERENCES expense_groups(id) ON DELETE CASCADE,
  from_member_id TEXT NOT NULL REFERENCES members(id),
  to_member_id TEXT NOT NULL REFERENCES members(id),
  amount_cents BIGINT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS group_members_user_idx ON group_members(user_id);
