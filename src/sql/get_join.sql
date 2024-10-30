BEGIN TRANSACTION;

WITH next_join AS (
    INSERT INTO running_join (ip, port, priority, timestamp)
    SELECT prefix, msbs, priority, $timestamp
    FROM pending_join
    ORDER BY priority DESC
    LIMIT $n
    RETURNING prefix, msbs
)

DELETE FROM pending_join
WHERE (prefix, msbs) IN (SELECT prefix, msbs FROM next_join);

COMMIT;
