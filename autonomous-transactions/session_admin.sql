------------------------------------------------------------------------------------------------------------------------
-- SETUP
------------------------------------------------------------------------------------------------------------------------
-- Restart from scratch
DROP EXTENSION IF EXISTS dblink;
DROP TABLE IF EXISTS sessions;
DROP function IF EXISTS insert_into_sessions(session_id integer, txid_current bigint, backend_pid integer);
DROP TABLE IF EXISTS accounts;

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

-- Create table to be able to reuse information from multiple sessions
CREATE TABLE sessions
(
    id integer PRIMARY KEY,
    txid_current numeric,
    backend_pid numeric
);

-- Create function that encapsulates the autonomous transaction
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

-- -- NB: simpler version but does not allow passing variable
-- create or replace function insert_into_sessions(id integer) returns void as $$
-- begin
--     perform dblink_connect('pragma','dbname=postgres');
--     perform dblink_exec('pragma','insert into sessions values (1, txid_current(), pg_backend_pid());');
--     perform dblink_exec('pragma','commit;');
--     perform dblink_disconnect('pragma');
-- end;
-- $$ language plpgsql;


------------------------------------------------------------------------------------------------------------------------
-- EXPERIMENT: Execute autonomous transaction without committing parent transaction
------------------------------------------------------------------------------------------------------------------------

SELECT * FROM sessions; -- is empty
SELECT * FROM accounts WHERE acc_no = 1; -- unchanged

-- Run session_1.sql

SELECT * FROM sessions; -- is filled with what session 1 gave it
SELECT * FROM accounts WHERE acc_no = 1; -- unchanged

-- As a consequence of this, we can access data from the `sessions` table (in particular, the current transaction ID
-- running in `session_1.sql`


------------------------------------------------------------------------------------------------------------------------
-- OUT OF SCOPE: Kill dblink connection if "duplicate connection name" error
------------------------------------------------------------------------------------------------------------------------

-- IF problem duplicate connection name, do this:
-- (ref: https://stackoverflow.com/questions/52262274/postgresql-error-duplicate-connection-name)
SELECT dblink_get_connections();
SELECT dblink_disconnect('pragma');
