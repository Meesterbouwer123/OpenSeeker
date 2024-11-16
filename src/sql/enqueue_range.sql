INSERT INTO pending_discovery VALUES ($prefix & ~(0xffffffff >> $msbs), $msbs, $priority);
