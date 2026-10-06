-- Exact expense splits are immutable allocations, distinct from the people
-- who contributed payment toward an expense.
CREATE TABLE IF NOT EXISTS expense_shares (
  expense_id TEXT NOT NULL REFERENCES expenses(id) ON DELETE CASCADE,
  member_id TEXT NOT NULL REFERENCES members(id),
  position INTEGER NOT NULL,
  amount_cents BIGINT NOT NULL CHECK (amount_cents >= 0),
  PRIMARY KEY(expense_id, member_id),
  UNIQUE(expense_id, position)
);
