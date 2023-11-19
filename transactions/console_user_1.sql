BEGIN;
-- get an AccessShareLock
SELECT * FROM users;
SELECT * FROM users;


ROLLBACK;
COMMIT;

