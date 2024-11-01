BEGIN TRANSACTION;
INSERT OR IGNORE INTO servers VALUES ($ip, $port);
INSERT INTO failed_legacy_pings VALUES ($ip, $port, $timestamp);
INSERT INTO pending_ping ($ip, $port, 5);
COMMIT TRANSACTION;
