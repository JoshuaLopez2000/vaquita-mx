ALTER TABLE expenses
  ADD COLUMN IF NOT EXISTS split_overpayment BOOLEAN NOT NULL DEFAULT true;

CREATE TABLE IF NOT EXISTS expense_retained_overpayments (
  expense_id TEXT NOT NULL REFERENCES expenses(id),
  member_id TEXT NOT NULL REFERENCES members(id),
  position INTEGER NOT NULL CHECK (position >= 0),
  amount_cents BIGINT NOT NULL CHECK (amount_cents > 0),
  PRIMARY KEY (expense_id, member_id),
  UNIQUE (expense_id, position)
);
