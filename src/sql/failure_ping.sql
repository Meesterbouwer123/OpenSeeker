BEGIN TRANSACTION;
INSERT OR IGNORE INTO servers VALUES ($ip, $port);
INSERT INTO failed_pings VALUES ($ip, $port, $timestamp);
COMMIT TRANSACTION;
