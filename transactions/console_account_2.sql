-- transfer
BEGIN;

UPDATE accounts SET balance=balance-400 WHERE id=2;
UPDATE accounts SET balance=balance+400 WHERE id=1;

COMMIT;

