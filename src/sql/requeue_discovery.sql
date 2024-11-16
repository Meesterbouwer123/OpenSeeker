BEGIN TRANSACTION;

INSERT OR REPLACE INTO pending_discovery (prefix, msbs, priority)
SELECT prefix, mbs, $priority
FROM running_discovery
WHERE prefix = $prefix AND msbs = $msbs;

DELETE FROM running_discovery WHERE prefix = $prefix and msbs = $msbs;
COMMIT;
