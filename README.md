# SQL playground

This project is a small playground for me to experiment and better understand some behaviors and internals of Postgres.

## Getting started

To run any experiment, get into the corresponding folder and start the `db` container:

```
cd chosen-experiment
docker compose up -d db
```

Then, execute the content of the main script (`session_admin.sql`) to set up the content of the DB and, if need be, also
execute the content of other scripts _each from a different session_ (`session_X.sql`).

Explanations for each experiment is contained in its particular README file.

## Experiments

- [`isolation level`](https://github.com/MaudGautier/sql-playground/tree/main/isolation-level) — Prove that the default
  isolation level in Postgres is "Read Committed".
- [`relation-level locks`](https://github.com/MaudGautier/sql-playground/tree/main/relation-level-locks) — Understand
  how locks are acquired at the relation (often, table) level:
    - Each transaction holds a lock on its own transactionID
    - If another transaction already has a lock on the relation, the transaction that tries to get the lock is blocked
      until the first one completes. A queue of blocked transactions is created in the meantime.
- [`row-level locks`](https://github.com/MaudGautier/sql-playground/tree/main/row-level-locks) — Understand how locks
  are acquired at the row level:
    - Info is not stored in the `pg_locks` table, but in the tuple (= version of the row), notably via the `xmax` field
    - When multiple transactions try to update the same row concurrently, queueing is ensured by a sequence of steps
      that involve acquiring the lock on the tuple and acquiring the lock on the last transactionID that updated the
      tuple. In particular, the queueing works because each transaction has an exclusive lock on itself => other
      transactions may update the row only once the one updating the row has completed.
- [`autonomous transactions`](https://github.com/MaudGautier/sql-playground/tree/main/autonomous-transactions) — A way
  to execute a transaction within a transaction so that I can access info about currently running transactions from any
  other session, _while the said transaction is still running_

  