-- Trying to update one row and see what locks are acquired
-- Do the same in parallel in session_2 and session_3 (and any number of sessions) => see how locks are held when
-- multi-transactions (i.e. several transactions concurrently trying to update the same row).

BEGIN;
SELECT insert_into_sessions(1, txid_current(), pg_backend_pid());
UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 1;
-- Go to session_admin (and replace pg_backend_pid by correct value) to see which locks are held.
-- SELECT * FROM locks_v WHERE pid = pg_backend_pid();

-- Do same in session_2
ROLLBACK;


