# Experiment - Acquiring locks on row-level

This experiment is adapted from [a PostgresPro blog post](https://postgrespro.com/blog/pgsql/5968005) (mainly follows
the blog post, with some additional research and adaptations).

## Theory - Main takeaways

### Row-level lock information is stored in a tuple (= row version) instead of RAM in PostgreSQL

- PostgreSQL stores information that a row is locked ONLY in the row version inside the data page, but NOT in the RAM.
- (Other DBMS use another system: escalation of locks, i.e. if the number of row-level locks is too high => we create a
  more general lock on the whole page or whole table)

Pros of storing in the row version (= tuple) instead of RAM:

- If it were stored in the RAM => one additional resource used for each row locked => a lot of memory used.
- By storing on row version => less memory occupied by locks
- In other words, **we can lock as many rows as we want without consuming any resource**.

Cons of storing in the row version (= tuple) instead of RAM:

- Other processes cannot be queued, since not stored in the RAM.
- Monitoring not possible either.

How to queue?

- Wait until completion of the locking transaction => we request a lock on the ID of the locking transaction.
- Since all transactions hold a lock on themselves in an exclusive mode, this is possible.
- As a consequence, **the number of locks used is proportional to the number of simultaneously running processes rather
  than to the number of rows being updated.**

### The `xmax` field of the current up-to-date version indicates whether the row is locked

When a row is deleted or updated, the ID of the transaction that "touched" it is written to the `xmax` field of the
current up-to-date version (informs on the transaction that deleted the tuple).
This `xmax` is used to indicate a lock: if `xmax` in a tuple matches an active (not yet completed) transaction, and we
want to update this very row, we need to wait until the transaction completes, and no additional indicator is needed.

When using the extension `pageinspect`, we can inspect pages, and see the `xmax` fields in
`heap_page_items(get_raw_page(TABLE_NAME, BLOCK_NUMBER))`. (NB: set `BLOCK_NUMBER` to 0 for this experiment, because
little data).

For more info on `heap_page_items`, `get_raw_page` or else, see
the [documentation of `pageinspect`](https://www.postgresql.org/docs/current/pageinspect.html).
Also, for more clarifying explanations on the heap table, refer
to [this medium article](https://muatik.medium.com/notes-on-postgresql-internals-4050340c9f4f).

Some precisions on `xmin` and `xmax`
from [the postgreSQL documentation](https://www.postgresql.org/docs/7.2/sql-syntax-columns.html):

- `xmin` = The identity (transaction ID) of the inserting transaction for this tuple.
- `xmax` = The identity (transaction ID) of the deleting transaction, or zero for an undeleted tuple.

### Tuple VS Row

- Row = logical representation of one entry
- Tuple = physical representation of that one entry, i.e. an individual state of each row. In other words, each update
  of a row creates a new tuple for the same logical row.

Whenever a row is updated, the previous tuple is marked as dead if it is not used by any other current transaction.

_Note to myself: this seems to be what the multi-version concurrency control (MVCC) is based on !!!_

References for that:

- [Question on stack overflow](https://stackoverflow.com/questions/19799282/whats-the-difference-between-a-tuple-and-a-row-in-postgres)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/7.2/sql-syntax-columns.html#:~:text=(Note%3A%20A%20tuple%20is%20an,xmax))
- [More detailed explanations about row versions](https://postgrespro.com/blog/pgsql/5967892)

## Experiments

### Experiment 1: Understand row-level locks defined by the `xmax` bit stored in heap pages

In `session_admin.sql`:
Show the row-level locks stored in the heap page: the `xmax` bit is set to the transaction ID (last transaction that
touched the row).

If the `xmax` value corresponds to an active transaction (seen in the `pg_stat_activity` table), it means that the lock
on this row is still held by that transaction.
With that, other transactions know they cannot update it.

### Experiment 2: Understand how row-level locks are acquired when multiple concurrent transactions (Where is the end of queues?)

In this second experiment, multiple transactions trying to update the same row are run
concurrently (`session_1.sql`, `session_2.sql`, `session_3.sql`, `session_4.sql`) and the `session_admin.sql` is used to
look at the locks.

This allows to observe the process of queueing, based on the acquirement of locks on:

- The transaction itself (ExclusiveLock on transactionID itself)
- The table being updated (RowExclusiveLock on `accounts` table)
- The tuple to be updated (ExclusiveLock on the tuple) - released right away if no other transaction currently having
  the lock on the row
- The blocking transaction that already has the lock on the row - only if other concurrent transaction blocking the
  process.

What goes on behind the scenes is the following.
When a transaction is going to change a row, it performs the following sequence of steps:

1. Acquires an exclusive lock on the tuple to be updated.
2. If `xmax` and information bits show that the row is locked, requests a lock on the `xmax` transaction ID.
3. Writes its own `xmax` and sets the required information bits.
4. Releases the tuple lock.

The reason behind having a double-level locking is so that the queue can be respected.
Otherwise (i.e. if there was only a lock on the row), once transaction1 has completed and released its lock on the row,
all other transactions (2, 3, 4, ...) could start at any time, without any order (=> the first that is awake will take
it).
If it was done like this, there is a possibility that one of the transactions may wait for its turn for infinitely long
(out of bad luck). This is called **lock starvation**.

By having the double-level locking, there is a queue that is being formed => this lock starvation should (????) be
prevented.

More detailed explanations (and possibly more accurate) directly
in [the blog post on which this experiment is based](https://postgrespro.com/blog/pgsql/5968005).
Some extra information on this in [this other article](https://www.cybertec-postgresql.com/en/row-locks-in-postgresql/).

Main takeaways:

- The queue is maintained by the tuple lock
- The beauty of that algorithm is that no session ever needs more than two locks in the lock table, so there is no
  danger of running out of memory.



