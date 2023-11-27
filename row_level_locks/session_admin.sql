------------------------------------------------------------------------------------------------------------------------
-- SETUP
------------------------------------------------------------------------------------------------------------------------
-- Restart from scratch
DROP VIEW IF EXISTS accounts_v;
DROP VIEW IF EXISTS locks_v;
DROP TABLE IF EXISTS accounts;
DROP EXTENSION IF EXISTS pageinspect;
DROP TABLE IF EXISTS sessions;
DROP EXTENSION IF EXISTS dblink;
-- SELECT dblink_get_connections();
-- SELECT dblink_disconnect('row_level_locks');


-- Create dataset
CREATE TABLE accounts
(
    acc_no integer PRIMARY KEY,
    amount numeric
);
INSERT INTO accounts
VALUES (1, 100.00),
       (2, 200.00),
       (3, 300.00);

CREATE EXTENSION pageinspect;

CREATE VIEW accounts_v AS
SELECT '(0,' || lp || ')'                                      AS ctid,
       t_xmax                                                  as xmax,
       CASE WHEN (t_infomask & 128) > 0 THEN 't' END           AS lock_only,
       CASE WHEN (t_infomask & 4096) > 0 THEN 't' END          AS is_multi,
       CASE WHEN (t_infomask2 & 8192) > 0 THEN 't' END         AS keys_upd,
       CASE WHEN (t_infomask & 16) > 0 THEN 't' END            AS keyshr_lock,
       CASE WHEN (t_infomask & 16 + 64) = 16 + 64 THEN 't' END AS shr_lock
FROM heap_page_items(get_raw_page('accounts', 0))
ORDER BY lp;
-- Original table for record (lp = line pointer, xmin and xmax set when row updated/created/deleted)
SELECT * from heap_page_items(get_raw_page('accounts',0));
-- Note: line pointer is a pointer to each heap tuple, and each heap tuple is a record data (see
-- https://muatik.medium.com/notes-on-postgresql-internals-4050340c9f4f)

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
-- QUESTION LEADING TO THESE EXPERIMENTS: Why don't we see differences in `pg_locks` when selecting 1 row or full table?
------------------------------------------------------------------------------------------------------------------------

-- Trying to see the differences in `pg_locks` when selecting only one row or full table (for update or only select).

BEGIN;
SELECT * FROM accounts;
SELECT locktype, relation::REGCLASS, virtualxid AS virtxid, transactionid AS xid, mode, granted
FROM pg_locks WHERE pid = pg_backend_pid() and relation = 'accounts'::REGCLASS;
ROLLBACK;

BEGIN;
SELECT * FROM accounts where acc_no=1;
SELECT locktype, relation::REGCLASS, virtualxid AS virtxid, transactionid AS xid, mode, granted
FROM pg_locks WHERE pid = pg_backend_pid() and relation = 'accounts'::REGCLASS;
-- Same lock info as for previous
ROLLBACK;

BEGIN;
SELECT * FROM accounts where acc_no=1 FOR UPDATE;
SELECT locktype, relation::REGCLASS, virtualxid AS virtxid, transactionid AS xid, mode, granted
FROM pg_locks WHERE pid = pg_backend_pid() and relation = 'accounts'::REGCLASS;
-- Same lock info as for previous
ROLLBACK;

BEGIN;
SELECT * FROM accounts FOR UPDATE;
SELECT locktype, relation::REGCLASS, virtualxid AS virtxid, transactionid AS xid, mode, granted
FROM pg_locks WHERE pid = pg_backend_pid() and relation = 'accounts'::REGCLASS;
-- Same lock info as for previous
ROLLBACK;

-- In each of these, we see the same information in `pg_locks`.
-- But we would have expected differences since it is either one row or the full table that is being selected => we
-- expect to see different lock levels.
--
-- Answer to this question = the way row-level locks are implemented in PostgreSQL. See experiments below.
-- In a nutshell, locks are not stored in the RAM to avoid using too much memory. Instead, stored at the level of
-- tuples (= row versions), via the `xmax` field. Can be accessed by looking at heap_pages.
-- Also, these are used to enqueue several transactions that want to update the same row.


------------------------------------------------------------------------------------------------------------------------
-- EXPERIMENT 1: Row-level locks -- Understand that row-level locks are defined by the `xmax` bit stored in heap pages
------------------------------------------------------------------------------------------------------------------------

-- EXCLUSIVE LOCK MODES
-- Case A: update
BEGIN;
UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 1;
UPDATE accounts SET acc_no = 20 WHERE acc_no = 2;
SELECT txid_current(); -- Current transaction ID
SELECT * FROM accounts_v LIMIT 2;
-- Same xmax (equals the current transactionID) for rows 1 and 2.
-- 2 has key updated.
ROLLBACK;

-- Case B: no update
BEGIN;
SELECT * FROM accounts WHERE acc_no = 1 FOR NO KEY UPDATE;
SELECT * FROM accounts WHERE acc_no = 2 FOR UPDATE;
SELECT txid_current(); -- Current transaction ID
SELECT * FROM accounts_v LIMIT 2;
-- Same xmax (equals the current transactionID) for rows 1 and 2.
-- Both have acquired the lock (lock_only=true) => the tuple is only locked, but not deleted and still live.
ROLLBACK;


-- SHARED LOCK MODES
BEGIN;
SELECT * FROM accounts WHERE acc_no = 1 FOR KEY SHARE;
SELECT * FROM accounts WHERE acc_no = 2 FOR SHARE;
SELECT * FROM accounts_v LIMIT 2;
-- key share lock bit is set (+ share lock for row 2)
ROLLBACK;


-- To see if xmax matches an active transaction
SELECT * FROM pg_stat_activity where backend_xid=(SELECT xmax FROM accounts_v LIMIT 1);
-- No row if transaction finished
-- But contains a row with 'state:active' if in the middle of a transaction that has a lock on this row.

------------------------------------------------------------------------------------------------------------------------
-- EXPERIMENT 2: Where is the end of queues?
------------------------------------------------------------------------------------------------------------------------

CREATE VIEW locks_v AS
SELECT pid,
       locktype,
       CASE locktype
           WHEN 'relation' THEN relation::regclass::text
           WHEN 'transactionid' THEN transactionid::text
           WHEN 'tuple' THEN relation::regclass::text || ':' || tuple::text
           END AS lockid,
       mode,
       granted
FROM pg_locks
WHERE locktype in ('relation', 'transactionid', 'tuple')
  AND (locktype != 'relation' OR relation = 'accounts'::regclass);


-- Goto session_1 to start a transaction

-- Look at locks
SELECT * FROM locks_v WHERE pid = (SELECT backend_pid FROM sessions WHERE id=1);
-- Transaction holds the lock on its own ID and on the table (as expected)

-- Goto session_2 to start a transaction

-- Look at locks
SELECT * FROM locks_v WHERE pid = (SELECT backend_pid FROM sessions WHERE id=2);
-- Transaction holds the lock on its own ID (locktype: transactionID, and lockID: txID) and on the table
-- (locktype: relation, and lockid: accounts). This is expected.
-- In addition, 2 more locks:
-- - Since the row is already locked by the first transaction, transaction2 asks for a lock on transaction1
--   (locktype: transactionID, and lockId: txID1). This is hanging (granted: false) until transaction1 is completed.
-- - A tuple lock (locktype: tuple, and lockID: accounts:1), i.e. a lock is acquired on the tuple (= physical
--   representation of the row that it wants to update).

-- The tuple lock is acquired for now, and will be released once the lock on the transactionID1 will be granted.
-- Why do we have to wait for a lock on txID1 ?
-- Because, xmax set to txID1 => after acquiring the tuple lock, transaction2 looks at xmax and information bits and
-- sees that the row is locked (cf below)
SELECT * FROM accounts_v LIMIT 1;
-- Therefore, it requires to have a lock on txID1.
-- Once transaction1 is completed (and thus the lock released) => transaction2 can proceed to write its own xmax, and
-- then, release the tuple lock.



-- Goto session_3 to start a transaction

-- Look at locks
SELECT * FROM locks_v WHERE pid = (SELECT backend_pid FROM sessions WHERE id=3);
-- transaction3 has acquired the lock on itself
-- Also acquires lock on relation accounts, and waits to be granted the lock on the tuple (will be when released by
-- transaction2).


-- Goto session_4 to start a transaction

-- Look at locks
SELECT * FROM locks_v WHERE pid = (SELECT backend_pid FROM sessions WHERE id=4);
-- Same as transaction3: wait for lock tuple to be granted.


-- To see the queue appearing
SELECT pid, wait_event_type, wait_event, pg_blocking_pids(pid)
FROM pg_stat_activity
WHERE backend_type = 'client backend';
-- We see that each transaction is blocked by the previous one (transaction3 by transaction2, transaction2 by
-- transaction1). transaction4 waits for both transaction2 (to release lock on row) and transaction3 (to release lock
-- on tuple).


-- Goto session1 and launch ROLLBACK

-- When we complete transaction1 (ROLLBACK) => transaction2 acquires the lock on it and it can proceed to write its own
-- xmax (txID2) in the heap page, and then release its lock on the tuple.
SELECT * FROM accounts_v LIMIT 1;
-- xmax is now set to tx

-- Same for other transactions -> waiting for transaction2 to complete to do the same (get lock on txID2 => write their
-- own xmax to heap page => release tuple lock)

-- Goto session2 and launch ROLLBACK.
-- Goto session3 and launch ROLLBACK.
-- Goto session4 and launch ROLLBACK.


