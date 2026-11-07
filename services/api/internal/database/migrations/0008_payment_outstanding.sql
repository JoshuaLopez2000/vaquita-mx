-- Completing a payment request revalidates the bilateral ledger inside the
-- completion transaction. This annotation records what was outstanding for the
-- debtor/creditor pair in that exact snapshot, so overpayments stay traceable
-- in the immutable event history without changing settlement behavior.
ALTER TABLE payment_provider_events
  ADD COLUMN outstanding_cents BIGINT;
