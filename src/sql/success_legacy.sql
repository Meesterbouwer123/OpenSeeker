BEGIN TRANSACTION;
INSERT OR IGNORE INTO servers VALUES ($ip, $port);
INSERT INTO successful_legacy_pings VALUES ($ip, $port, $timestamp, $max_players, $current_players, $motd);
INSERT INTO pending_ping ($ip, $port, $priority);
COMMIT TRANSACTION;
