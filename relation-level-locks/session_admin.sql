------------------------------------------------------------------------------------------------------------------------
-- SETUP
------------------------------------------------------------------------------------------------------------------------
-- Restart from scratch
DROP TABLE IF EXISTS accounts;

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


------------------------------------------------------------------------------------------------------------------------
-- PRE-EXPERIMENT: Which locks are held in a transaction? (Looking at `pg_locks`)
------------------------------------------------------------------------------------------------------------------------

-- Get process ID of the backend process
SELECT pg_backend_pid(); -- 21917

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
WHERE pid = 21927; -- background PID of session_1
-- At this stage, we have a RowExclusiveLock on accounts and on the index (created for the primary_key)
-- Also an additional lock on the transaction id
-- As expected, this is exactly identical to the locks held when run just above in session_admin.sql.


-- Run session_2.sql and look at pg_locks
SELECT locktype, relation::REGCLASS, virtualxid AS virtxid, transactionid AS xid, mode, granted
FROM pg_locks
WHERE pid = 21929; -- background PID of session_2
-- We see that session_2 (creating index) is trying to get lock on relation accounts, but it is not granted
-- (granted = false) => it is hanging

-- Find blocking PID for session_2
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

