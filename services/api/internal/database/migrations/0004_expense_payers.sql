CREATE TABLE IF NOT EXISTS expense_payers (
  expense_id TEXT NOT NULL REFERENCES expenses(id) ON DELETE CASCADE,
  member_id TEXT NOT NULL REFERENCES members(id),
  position INTEGER NOT NULL CHECK (position >= 0),
  amount_cents BIGINT NOT NULL CHECK (amount_cents > 0),
  PRIMARY KEY(expense_id, member_id),
  UNIQUE(expense_id, position)
);

-- Existing immutable expenses retain their single payer representation and
-- receive an equivalent contribution so readers can use one model safely.
INSERT INTO expense_payers(expense_id, member_id, position, amount_cents)
SELECT id, payer_id, 0, amount_cents
FROM expenses
ON CONFLICT (expense_id, member_id) DO NOTHING;
