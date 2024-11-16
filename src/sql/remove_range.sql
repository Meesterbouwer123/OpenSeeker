DELETE FROM pending_discovery WHERE prefix = $prefix & ~(0xffffffff >> $msbs) and msbs = $msbs;
