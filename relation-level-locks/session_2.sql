-- RUN SECOND
SELECT insert_into_sessions(2, txid_current(), pg_backend_pid());
CREATE INDEX ON accounts(acc_no); -- This is hanging
-- Go to session_admin to read the `pg_locks` table (can't be done here since the session is hanging)
ROLLBACK;


