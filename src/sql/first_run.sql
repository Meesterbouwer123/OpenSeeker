PRAGMA user_version = 0;
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS excluded (
    prefix INT NOT NULL CHECK(prefix >= 0 AND prefix < 1 << 32 AND prefix & (0xffffffff >> msbs) == 0),
    msbs INT NOT NULL CHECK(msbs >= 0 AND msbs <= 32),
    reason TEXT,

    PRIMARY KEY(prefix, msbs)
) STRICT;

CREATE INDEX IF NOT EXISTS idx_excluded_msbs ON excluded (msbs);

CREATE TABLE IF NOT EXISTS pending_discovery (
    prefix INT NOT NULL CHECK(prefix >= 0 AND prefix < 1 << 32 AND prefix & (0xffffffff >> msbs) == 0),
    msbs INT NOT NULL CHECK(msbs >= 0 AND msbs <= 32),
    priority INT NOT NULL CHECK(priority >= 0 AND priority < 1 << 8),

    PRIMARY KEY(prefix, msbs)
) STRICT;

CREATE INDEX IF NOT EXISTS idx_pending_discovery_priority ON pending_discovery (priority DESC);

CREATE TABLE IF NOT EXISTS running_discovery (
    prefix INT NOT NULL CHECK(prefix >= 0 AND prefix < 1 << 32 AND prefix & (0xffffffff >> msbs) == 0),
    msbs INT NOT NULL CHECK(msbs >= 0 AND msbs <= 32),
    timestamp INT NOT NULL,
    packets_per_sec INT NOT NULL,

    PRIMARY KEY(prefix, msbs)
) STRICT;

CREATE TABLE IF NOT EXISTS pending_ping (
    ip INT NOT NULL CHECK(ip >= 0 AND ip < 1 << 32),
    port INT NOT NULL CHECK(port >= 0 AND port < 1 << 16),
    priority INT NOT NULL CHECK(priority >= 0 AND priority < 1 << 8),

    PRIMARY KEY(ip, port)
) STRICT;

CREATE INDEX IF NOT EXISTS idx_pending_ping_priority ON pending_ping (priority DESC);

CREATE TABLE IF NOT EXISTS running_ping (
    ip INT NOT NULL CHECK(ip >= 0 AND ip < 1 << 32),
    port INT NOT NULL CHECK(port >= 0 AND port < 1 << 16),
    priority INT NOT NULL CHECK(priority >= 0 AND priority < 1 << 8),

    timestamp INT NOT NULL,
    PRIMARY KEY(ip, port)
) STRICT;

CREATE TABLE IF NOT EXISTS pending_legacy (
    ip INT NOT NULL CHECK(ip >= 0 AND ip < 1 << 32),
    port INT NOT NULL CHECK(port >= 0 AND port < 1 << 16),
    priority INT NOT NULL CHECK(priority >= 0 AND priority < 1 << 8),

    PRIMARY KEY(ip, port)
) STRICT;

CREATE TABLE IF NOT EXISTS running_legacy (
    ip INT NOT NULL CHECK(ip >= 0 AND ip < 1 << 32),
    port INT NOT NULL CHECK(port >= 0 AND port < 1 << 16),
    priority INT NOT NULL CHECK(priority >= 0 AND priority < 1 << 8),
    timestamp INT NOT NULL,

    PRIMARY KEY(ip, port)
) STRICT;

CREATE INDEX IF NOT EXISTS idx_pending_legacy_priority ON pending_legacy (priority DESC);

CREATE TABLE IF NOT EXISTS pending_join (
    ip INT NOT NULL CHECK(ip >= 0 AND ip < 1 << 32),
    port INT NOT NULL CHECK(port >= 0 AND port < 1 << 16),
    priority INT NOT NULL CHECK(priority >= 0 AND priority < 1 << 8),

    PRIMARY KEY(ip, port)
) STRICT;

CREATE TABLE IF NOT EXISTS running_join (
    ip INT NOT NULL CHECK(ip >= 0 AND ip < 1 << 32),
    port INT NOT NULL CHECK(port >= 0 AND port < 1 << 16),
    priority INT NOT NULL CHECK(priority >= 0 AND priority < 1 << 8),
    timestamp INT NOT NULL,

    PRIMARY KEY(ip, port)
) STRICT;

CREATE INDEX IF NOT EXISTS idx_pending_join_priority ON pending_join (priority DESC);

CREATE TABLE IF NOT EXISTS servers (
    ip INT NOT NULL CHECK(ip >= 0 AND ip < 1 << 32),
    port INT NOT NULL CHECK(port >= 0 AND port < 1 << 16),

    PRIMARY KEY(ip, port)
) STRICT;


CREATE TABLE IF NOT EXISTS discoveries (
    ip INT NOT NULL CHECK(ip >= 0 AND ip < 1 << 32),
    port INT NOT NULL CHECK(port >= 0 AND port < 1 << 16),
    timestamp INT NOT NULL,

    FOREIGN KEY (ip, port) REFERENCES servers(ip, port) ON DELETE CASCADE
) STRICT;

CREATE TABLE IF NOT EXISTS favicons (
    id INTEGER PRIMARY KEY,
    data BLOB UNIQUE
) STRICT;

CREATE TABLE IF NOT EXISTS failed_pings (
    ip INT NOT NULL CHECK(ip >= 0 AND ip < 1 << 32),
    port INT NOT NULL CHECK(port >= 0 AND port < 1 << 16),
    timestamp INT NOT NULL,

    FOREIGN KEY (ip, port) REFERENCES servers(ip, port) ON DELETE CASCADE
) STRICT;

CREATE TABLE IF NOT EXISTS successful_pings (
    ip INT NOT NULL CHECK(ip >= 0 AND ip < 1 << 32),
    port INT NOT NULL CHECK(port >= 0 AND port < 1 << 16),
    timestamp INT NOT NULL,
    enforces_secure_chat INT,
    prevents_chat_reports INT,
    version_name TEXT,
    version_protocol INT NOT NULL,
    favicon_id INT,
    max_players INT,
    current_players INT,
    -- full text component json with all the bells and whistles.
    description_json TEXT,
    -- all formatting stripped
    description_text TEXT,
    extra_json TEXT,

    FOREIGN KEY (ip, port) REFERENCES servers(ip, port) ON DELETE CASCADE,
    FOREIGN KEY (favicon_id) REFERENCES favicons(id) ON DELETE RESTRICT
    CHECK(description_json NOT NULL AND NOT description_text IS NULL),
) STRICT;

CREATE TABLE IF NOT EXISTS failed_legacy_pings (
    ip INT NOT NULL CHECK(ip >= 0 AND ip < 1 << 32),
    port INT NOT NULL CHECK(port >= 0 AND port < 1 << 16),
    timestamp INT NOT NULL,

    FOREIGN KEY (ip, port) REFERENCES servers(ip, port) ON DELETE CASCADE
) STRICT;

CREATE TABLE IF NOT EXISTS successful_legacy_pings (
    id INTEGER PRIMARY KEY,

    ip INT NOT NULL CHECK(ip >= 0 AND ip < 1 << 32),
    port INT NOT NULL CHECK(port >= 0 AND port < 1 << 16),
    timestamp INT NOT NULL,
    max_players INT NOT NULL,
    current_players INT NOT NULL,
    motd TEXT NOT NULL,

    FOREIGN KEY (ip, port) REFERENCES servers(ip, port) ON DELETE CASCADE
) STRICT;

CREATE TABLE IF NOT EXISTS failed_joins (
    ip INT NOT NULL CHECK(ip >= 0 AND ip < 1 << 32),
    port INT NOT NULL CHECK(port >= 0 AND port < 1 << 16),
    timestamp INT NOT NULL,
    reason INT NOT NULL,

    FOREIGN KEY (ip, port) REFERENCES servers(ip, port) ON DELETE CASCADE
) STRICT;

CREATE TABLE IF NOT EXISTS successful_joins (
    id INTEGER PRIMARY KEY,

    ip INT NOT NULL CHECK(ip >= 0 AND ip < 1 << 32),
    port INT NOT NULL CHECK(port >= 0 AND port < 1 << 16),
    timestamp INT NOT NULL,
    -- figure out what to put here when we have a joiner
    FOREIGN KEY (ip, port) REFERENCES servers(ip, port) ON DELETE CASCADE
) STRICT;

CREATE TABLE IF NOT EXISTS players (
    id INTEGER PRIMARY KEY,

    uuid_low INT NOT NULL,
    uuid_high INT NOT NULL,
    name BLOB NOT NULL,

   UNIQUE (uuid_high, uuid_low)
) STRICT;

CREATE TABLE IF NOT EXISTS ping_players (
    player_id INT NOT NULL,
    ping_id INT,
    join_id INT,

    FOREIGN KEY (player_id) REFERENCES players(id) ON DELETE CASCADE,
    FOREIGN KEY (ping_id) REFERENCES successful_pings(id) ON DELETE CASCADE,
    FOREIGN KEY (join_id) REFERENCES successful_joins(id) ON DELETE CASCADE,
    CHECK (ping_id NOT NULL OR join_id NOT NULL)
) STRICT;

CREATE TABLE IF NOT EXISTS authorized_public_keys (
    public_key BLOB UNIQUE CHECK(length(public_key) = 32)
) STRICT;
