------------------------------------------------------------------------------------------------------------------------
-- SETUP
------------------------------------------------------------------------------------------------------------------------
-- Restart from scratch
DROP TABLE IF EXISTS accounts;
DROP TABLE IF EXISTS sessions;
DROP EXTENSION IF EXISTS dblink;

-- Create table accounts
CREATE TABLE accounts
(
    acc_no integer PRIMARY KEY,
    amount numeric
);
INSERT INTO accounts
VALUES (1, 1000.00),
       (2, 2000.00),
       (3, 3000.00);

-- Create function encapsulating an autonomous transaction (see experiment `autonomous-transactions` for explanations)
-- This will allow sharing current transaction ID from each session to this session
create extension dblink;
create or replace function insert_into_sessions(session_id integer, txid_current bigint, backend_pid integer) returns void as
$$
declare
    SqlCommand TEXT;
begin
    SqlCommand := 'insert into sessions (id, txid_current, backend_pid)
    values (' || session_id || ', ' || txid_current || ', ' || backend_pid || ')
    ON CONFLICT (id) DO UPDATE
        SET txid_current = excluded.txid_current,
            backend_pid  = excluded.backend_pid;';
    perform dblink_connect('pragma', 'dbname=postgres');
    perform dblink_exec('pragma', SqlCommand);
    perform dblink_exec('pragma', 'commit;');
    perform dblink_disconnect('pragma');
end
$$ language plpgsql;
CREATE TABLE sessions
(
    id integer PRIMARY KEY,
    txid_current numeric,
    backend_pid numeric
);


------------------------------------------------------------------------------------------------------------------------
-- PRE-EXPERIMENT: Which locks are held in a transaction? (Looking at `pg_locks`)
------------------------------------------------------------------------------------------------------------------------

-- Get process ID of the backend process
SELECT pg_backend_pid();

-- Look at pg_locks
SELECT locktype, relation::REGCLASS, virtualxid AS virtxid, transactionid AS xid, mode, granted
FROM pg_locks WHERE pid = pg_backend_pid();
-- We have a virtualxid (= virtual transaction ID)
-- A transaction always holds an Exclusive lock on its own ID (virtual in this case: the pg_locks is queried).

-- What happens when in a transaction?
BEGIN;
UPDATE accounts SET amount = amount + 100 WHERE acc_no = 1;
SELECT locktype, relation::REGCLASS, virtualxid AS virtxid, transactionid AS xid, mode, granted
FROM pg_locks WHERE pid = pg_backend_pid();
-- At this stage, we have a RowExclusiveLock on accounts and on the index (created for the primary_key)
-- Also an additional lock on the transaction id
ROLLBACK;

------------------------------------------------------------------------------------------------------------------------
-- EXPERIMENT: Relation-level locks when multi-transactions => queueing/hanging
------------------------------------------------------------------------------------------------------------------------

-- Run session_1.sql and look at pg_locks
SELECT locktype, relation::REGCLASS, virtualxid AS virtxid, transactionid AS xid, mode, granted
FROM pg_locks
WHERE pid = (SELECT backend_pid FROM sessions WHERE id=1); -- background PID of session_1
-- At this stage, we have a RowExclusiveLock on accounts and on the index (created for the primary_key)
-- Also an additional lock on the transaction id
-- As expected, this is exactly identical to the locks held when run just above in session_admin.sql.


-- Run session_2.sql and look at pg_locks
SELECT locktype, relation::REGCLASS, virtualxid AS virtxid, transactionid AS xid, mode, granted
FROM pg_locks
WHERE pid = (SELECT backend_pid FROM sessions WHERE id=2); -- background PID of session_2
-- We see that session_2 (creating index) is trying to get lock on relation accounts, but it is not granted
-- (granted = false) => it is hanging

-- Find blocking PID for session_2
SELECT backend_pid FROM sessions WHERE id=2;
SELECT pg_blocking_pids(21929);
-- We see that what is blocking is {21927}, i.e. process id from session_1

-- Get information on the sessions to which the PIDs found pertain
SELECT * FROM pg_stat_activity
WHERE pid = ANY(pg_blocking_pids(21929));


------------------------------------------------------------------------------------------------------------------------
-- OUT OF SCOPE: KILL A PROCESS
------------------------------------------------------------------------------------------------------------------------

-- To terminate idle process (when hanging because waiting for lock)
-- Either commit/rollback the blocking transaction
-- Or do this:
select * from pg_stat_activity;
SELECT pid , query, * from pg_stat_activity
  WHERE state LIKE '%idle%' ORDER BY xact_start;
-- select pg_cancel_backend(21927); -- soft version
-- select pg_terminate_backend(21927); -- hard version

