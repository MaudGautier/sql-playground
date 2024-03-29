-- Run this after having started session_1

BEGIN;
SELECT insert_into_sessions(2, txid_current(), pg_backend_pid());
UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 1;
-- Go to session_admin (and replace pg_backend_pid by correct value) to see which locks are held.
-- SELECT * FROM locks_v WHERE pid = pg_backend_pid();

-- Do same in session_3
ROLLBACK;
