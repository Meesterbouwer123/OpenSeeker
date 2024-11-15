SELECT excluded.prefix, excluded.msbs
FROM excluded
WHERE excluded.msbs >= $msbs
        AND excluded.prefix & ~(0xffffffff >> (32 - $msbs)) == $prefix
