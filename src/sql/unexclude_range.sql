DELETE FROM excluded WHERE prefix = $prefix & ~(0xffffffff >> $msbs) AND msbs = $msbs
