BEGIN TRANSACTION;

WITH next_ping AS (
    INSERT INTO running_ping (ip, port, priority, timestamp)
    SELECT prefix, msbs, priority, $timestamp
    FROM pending_ping
    ORDER BY priority DESC
    LIMIT $n
    RETURNING prefix, msbs
)

DELETE FROM pending_ping
WHERE (prefix, msbs) IN (SELECT prefix, msbs FROM next_ping);

COMMIT;
