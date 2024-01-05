# Relation-level locks

This experiment is based on [a PostgresPro blog post](https://habr.com/en/companies/postgrespro/articles/500714/)

To reproduce, follow what's indicated in `session_admin.sql`.

In a nutshell, here are the learnings from this experiment:

- Each transaction always holds an exclusive lock on its own ID (whether real or virtual)
- The first transaction that tries to update a table acquires the lock on the said table
- If another transaction tries to access it before the first transaction has released its lock (with a mode that is
  incompatible with the current locks held), it is blocked until the first transaction is completed (commits or
  rollback). Instead, it is enqueued behind it.
  NB: We can identify the blocking transactions by looking at `pg_blocking_pids`.

NB: If we added another request in transaction 1 (`session_1.sql`) that a. requires a lock that is already held by
transaction 2 (`session_2.sql`), and b. is _launched_ after the lock has been held by transaction 2, then we'd be in a
deadlock situation where transaction 1 waits for transaction 2 to complete and transaction 2 waits for transaction 1 to
complete.
See `deadlock` folder experiment for a full implementation of this situation.

