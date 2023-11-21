-- setup
CREATE TABLE users (id int UNIQUE, username text);

INSERT INTO users (id, username)
VALUES (1, 'igor'), (2, 'bob'), (3, 'john'), (4, 'susan');

CREATE TABLE items (id int, description text);
INSERT INTO items (id, description)
VALUES (1, 'stuff 1'), (2, 'stuff 2'), (3, 'stuff 3'), (4, 'stuff 4');

SELECT * FROM users;


-- relation is a number, but can be cast to something more readable.
SELECT locktype, relation::regclass, mode, pid
from pg_locks;


-- locks with current pid filtered out
SELECT locktype, relation::regclass, mode, pid
from pg_locks
where pid != pg_backend_pid();



DROP TABLE users;

CREATE TABLE accounts (id int UNIQUE, balance int);


INSERT INTO accounts (id, balance)
VALUES (1, 1000), (2, 1000);

SELECT * FROM accounts;


SELECT * from pg_settings;


SHOW default_transaction_isolation;


