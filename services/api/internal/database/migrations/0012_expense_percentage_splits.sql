-- Percentage splits store fixed-point basis points (100 bps = 1.00%,
-- summing to 10000 bps) alongside the immutable final centavo share
-- computed at expense creation time.
ALTER TABLE expense_shares
  ADD COLUMN IF NOT EXISTS percentage_bps INTEGER
  CHECK (percentage_bps IS NULL OR (percentage_bps > 0 AND percentage_bps <= 10000));
