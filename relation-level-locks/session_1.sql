-- Get process ID of the backend process
SELECT pg_backend_pid(); -- 21927

-- RUN FIRST
-- Look at how pg_locks evolve while updating a row
BEGIN;
UPDATE accounts SET amount = amount + 100 WHERE acc_no = 1;
-- Go to session_admin to look at the `pg_locks` (or run here, cf below)
SELECT locktype, relation::REGCLASS, virtualxid AS virtxid, transactionid AS xid, mode, granted
FROM pg_locks WHERE pid = pg_backend_pid();
-- At this stage, we have a RowExclusiveLock on accounts and on the index (created for the primary_key)
-- Also an additional lock on the transaction id

-- Go to session_2.sql to run another request that is hanging

ROLLBACK;
-- When the transaction is completed, the locks are released and index from console2 is created
