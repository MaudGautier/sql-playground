-- Run this after having started session_3

BEGIN;
SELECT txid_current(), pg_backend_pid();
UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 1;
-- Go to session_admin (and replace pg_backend_pid by correct value) to see which locks are held.
-- SELECT * FROM locks_v WHERE pid = pg_backend_pid();
ROLLBACK;
