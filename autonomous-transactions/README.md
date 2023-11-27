# Autonomous transactions

## Context

For some experiments (row-level locks, relation-level locks, deadlock, ...), we run concurrent transactions in separate
sessions (usually `session_1`, `session_2`, ...) and we use yet another 'master' session (usually `session_admin`) to
look at certain pieces of information on postgres tables (notably `pg_locks`, but others possible).

In particular, sometimes we need to record certain variables (like the `pg_backend_id` of each concurrent session) to be
able to look at them from the master/admin session.

One way to do this is to write down the information manually while executing concurrent sessions, and then write them
manually in the script of the master/admin session, but that is pretty tedious.
Another way would be to record these pieces of information (variables) in a shared table (e.g. `sessions` table) so that
the master/admin session can read from it and variables can be shared.

This works for `pg_backend_id`. However, if we need other pieces of information relative to the current transaction
_while it is being run_ (e.g. current transaction ID: `txid_current()`), it is **not** possible because the info won't
be committed into the shared table before the whole transaction is completed, and we may want to monitor what is
happening **before** the said transaction is committed.

Hence, I searched for a way to run a "transaction within a transaction".
Such "subtransactions" are _not_ supported natively by PostgreSQL (
see [this stack exchange question](https://dba.stackexchange.com/questions/81011/transactions-within-a-transaction)).

There are however some workarounds for this:

- The PostgresPro company has created a feature to support such "subtransactions" but it seems to be solely in their
  software (???). See [their documentation about it](https://postgrespro.com/docs/enterprise/11/atx). _NB: I tried
  writing a script using their syntax, and it doesn't work => makes me think this is only in their own software, but not
  so sure I understand._
- Apparently, it can also be done using the `pg_background` extension.
  Explanations [here](https://blog.dalibo.com/2016/08/19/Autonoumous_transactions_support_in_PostgreSQL.html). They seem
  to say it's better than using the third option (`db_link`) but I don't really understand why.
- Also possible to do it with `db_link` as
  explained [here](https://raghavt.blog/autonomous-transaction-in-postgresql-9-1/). This is the option I am using in
  this experiment.

NB: The recognized name for this seems to be "autonomous transaction".
However, some people also call this "subtransactions" (+ that is the keyword used in the PostgresPro Entreprise
software). I use both interchangeably here.

## Experiment: Create autonomous transactions

The autonomous transaction (`INSERT INTO sessions ...`) is encapsulated in a function (`insert_into_sessions`) that
uses the `dblink` extension to get another connection to the database (see `session_admin.sql`).

This function can then be called in the middle of another (parent) transaction (see `session_1.sql`).
When executing the parent transaction, even if it has not been committed, the autonomous transaction (= child
transaction) is committed.
In practice, as a consequence of this autonomous transaction, data committed into the `sessions` table is accessible
from any other session _while the parent transaction is still running_.

NB: It is mandatory to execute `txid_current()` and `pg_backend_pid()` from the session containing the parent
transaction and pass them as variables to the function encapsulating the automomous transactions, so that their values
correspond to what we search for. 
