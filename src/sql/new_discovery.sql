BEGIN TRANSACTION;
INSERT OR IGNORE INTO servers VALUES ($ip, $port);
INSERT INTO discoveries VALUES ($ip, $port, $timestamp);
INSERT INTO pending_legacy VALUES ($ip, $port, $priority);
COMMIT TRANSACTION;
