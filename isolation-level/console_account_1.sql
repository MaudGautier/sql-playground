-- alice
BEGIN;

SELECT * FROM accounts WHERE id=1;

-- do transfer !

SELECT * FROM accounts WHERE id=2;

COMMIT;

