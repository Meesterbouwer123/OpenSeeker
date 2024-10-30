BEGIN TRANSACTION;
INSERT OR IGNORE INTO servers VALUES ($ip, $port);
INSERT INTO failed_joins VALUES ($ip, $port, $timestamp, $reason);
COMMIT TRANSACTION;
