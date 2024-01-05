# Experiment - Isolation level

This experiment was made with Laurent: we wondered about the default isolation level in Postgres.

To do this, we reproduced an example explained in Martin Kleppmann's
book [Designing Data-Intensive Applications](https://www.oreilly.com/library/view/designing-data-intensive-applications/9781491903063/).

Here is what happens:

- We have two accounts (IDs: 1 and 2) and we assume we want to transfer $400 from account 2 to account 1
- In the meantime, within a single transaction, a person reads the values in the two accounts: one of the reads
  (account 1) occurs before the transfer begins, the other one (account 2) after the transfer has been done and
  committed.
- Observations: we see that the values read correspond to what has been committed before OR while the read transaction
  was occurring. This means that we are in a "Read Committed" isolation level.
- Note: If we were in a "Snapshot Isolation" isolation level, then we would read values that were committed BEFORE the
  read transaction began.

The isolation level can be read with ` SHOW default_transaction_isolation`;

