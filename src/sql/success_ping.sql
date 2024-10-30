BEGIN TRANSACTION;
INSERT OR IGNORE INTO servers VALUES ($ip, $port);
INSERT INTO successful_pings VALUES (
    $ip,
    $port,
    $timestamp,
    $enforces_secure_chat,
    $prevents_chat_reports,
    $version_name,
    $version_protocol,
    $favicon_id,
    $max_players,
    $current_players,
    $description_json,
    $description_text,
    $extra_json,
);
INSERT INTO pending_join ($ip, $port, $priority);
COMMIT TRANSACTION;
