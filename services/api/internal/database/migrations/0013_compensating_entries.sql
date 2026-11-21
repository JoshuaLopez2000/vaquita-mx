CREATE TABLE IF NOT EXISTS expense_reversals (
  id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL REFERENCES expense_groups(id) ON DELETE CASCADE,
  original_expense_id TEXT NOT NULL UNIQUE REFERENCES expenses(id) ON DELETE RESTRICT,
  actor_user_id TEXT NOT NULL REFERENCES users(id),
  actor_member_id TEXT NOT NULL REFERENCES members(id),
  reason TEXT NOT NULL CHECK (length(trim(reason)) BETWEEN 1 AND 500),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS expense_reversals_group_idx
  ON expense_reversals(group_id, created_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS settlement_reversals (
  id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL REFERENCES expense_groups(id) ON DELETE CASCADE,
  original_settlement_id TEXT NOT NULL UNIQUE REFERENCES settlements(id) ON DELETE RESTRICT,
  actor_user_id TEXT NOT NULL REFERENCES users(id),
  actor_member_id TEXT NOT NULL REFERENCES members(id),
  reason TEXT NOT NULL CHECK (length(trim(reason)) BETWEEN 1 AND 500),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS settlement_reversals_group_idx
  ON settlement_reversals(group_id, created_at DESC, id DESC);

ALTER TABLE expenses
  ADD COLUMN IF NOT EXISTS replaces_expense_id TEXT REFERENCES expenses(id);

CREATE UNIQUE INDEX IF NOT EXISTS expenses_replaces_expense_unique_idx
  ON expenses(replaces_expense_id)
  WHERE replaces_expense_id IS NOT NULL;

ALTER TABLE settlements
  ADD COLUMN IF NOT EXISTS replaces_settlement_id TEXT REFERENCES settlements(id);

CREATE UNIQUE INDEX IF NOT EXISTS settlements_replaces_settlement_unique_idx
  ON settlements(replaces_settlement_id)
  WHERE replaces_settlement_id IS NOT NULL;

ALTER TABLE offline_sync_entries
  DROP CONSTRAINT IF EXISTS offline_sync_entries_entity_type_check;

ALTER TABLE offline_sync_entries
  ADD CONSTRAINT offline_sync_entries_entity_type_check
  CHECK (entity_type IN ('expense', 'settlement', 'expense_reversal', 'settlement_reversal'));
