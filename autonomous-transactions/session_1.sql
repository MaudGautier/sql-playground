SELECT * FROM sessions;
SELECT pg_backend_pid();

BEGIN;
SELECT txid_current();
SELECT insert_into_sessions(1, txid_current(), pg_backend_pid());
SELECT * FROM sessions;
UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 1;
SELECT * FROM accounts WHERE acc_no = 1;
-- Go to session_admin.sql => session has been committed (= autonomous transaction), but accounts is still unchanged
-- (until this transaction is committed)
ROLLBACK;

