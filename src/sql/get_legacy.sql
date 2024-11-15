BEGIN TRANSACTION;

WITH next_legacy AS (
    INSERT INTO running_legacy (ip, port, priority, timestamp)
    SELECT prefix, msbs, priority, $timestamp
    FROM pending_legacy
    ORDER BY priority DESC
    LIMIT $n
    RETURNING prefix, msbs
)

DELETE FROM pending_legacy
WHERE (prefix, msbs) IN (SELECT prefix, msbs FROM next_legacy);

COMMIT;
