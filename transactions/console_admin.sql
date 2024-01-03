CREATE TABLE accounts (id int UNIQUE, balance int);


INSERT INTO accounts (id, balance)
VALUES (1, 1000), (2, 1000);

SELECT * FROM accounts;


SELECT * from pg_settings;


SHOW default_transaction_isolation;


