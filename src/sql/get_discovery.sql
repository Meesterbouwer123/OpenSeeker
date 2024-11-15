BEGIN TRANSACTION;

WITH next_discovery AS (
    INSERT INTO running_discovery (prefix, msbs, priority, timestamp, packets_per_sec)
    SELECT prefix, msbs, priority, $timestamp, $pps
    FROM pending_discovery
    ORDER BY priority DESC
    LIMIT 1
    RETURNING prefix, msbs
)

DELETE FROM pending_discovery
WHERE (prefix, msbs) IN (SELECT prefix, msbs FROM next_discovery);

COMMIT;
