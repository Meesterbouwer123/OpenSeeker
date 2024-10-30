BEGIN TRANSACTION;
INSERT OR IGNORE INTO servers VALUES ($ip, $port);
INSERT INTO successful_joins VALUES ($ip, $port, $timestamp);
COMMIT TRANSACTION;
