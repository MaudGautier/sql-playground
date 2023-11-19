BEGIN;
INSERT INTO users (id, username) VALUES (6, 'jane');
SELECT * from users;
INSERT INTO users (id, username) VALUES (5, 'jane');
INSERT INTO users (id, username) VALUES (1, 'jane');
SELECT * from users where id=5;
COMMIT;

-- TODO funny it doesn't commit successful things

-- SELECT * from users;