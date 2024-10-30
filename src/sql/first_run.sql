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

CREATE TABLE IF NOT EXISTS pending_ping (
    ip INT NOT NULL CHECK(ip >= 0 AND ip < 1 << 32),
    port INT NOT NULL CHECK(port >= 0 AND port < 1 << 16),
    priority INT NOT NULL CHECK(priority >= 0 AND priority < 1 << 8),
    PRIMARY KEY(ip, port)
) STRICT;

CREATE INDEX IF NOT EXISTS idx_pending_ping_priority ON pending_ping (priority DESC);

CREATE TABLE IF NOT EXISTS pending_legacy (
    ip INT NOT NULL CHECK(ip >= 0 AND ip < 1 << 32),
    port INT NOT NULL CHECK(port >= 0 AND port < 1 << 16),
    priority INT NOT NULL CHECK(priority >= 0 AND priority < 1 << 8),
    PRIMARY KEY(ip, port)
) STRICT;

CREATE INDEX IF NOT EXISTS idx_pending_legacy_priority ON pending_legacy (priority DESC);

CREATE TABLE IF NOT EXISTS pending_join (
    ip INT NOT NULL CHECK(ip >= 0 AND ip < 1 << 32),
    port INT NOT NULL CHECK(port >= 0 AND port < 1 << 16),
    priority INT NOT NULL CHECK(priority >= 0 AND priority < 1 << 8),
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

    FOREIGN KEY (ip, port) REFERENCES servers(ip, port)
) STRICT;

CREATE TABLE IF NOT EXISTS favicons (
    data BLOB PRIMARY KEY
) STRICT;

CREATE TABLE IF NOT EXISTS failed_pings (
    ip INT NOT NULL CHECK(ip >= 0 AND ip < 1 << 32),
    port INT NOT NULL CHECK(port >= 0 AND port < 1 << 16),
    timestamp INT NOT NULL,
    FOREIGN KEY (ip, port) REFERENCES servers(ip, port)
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
    description_json TEXT,
    description_text TEXT,
    extra_json TEXT,
    FOREIGN KEY (ip, port) REFERENCES servers(ip, port),
    FOREIGN KEY (favicon_id) REFERENCES favicons(_rowid_)
) STRICT;

CREATE TABLE IF NOT EXISTS failed_legacy_pings (
    ip INT NOT NULL CHECK(ip >= 0 AND ip < 1 << 32),
    port INT NOT NULL CHECK(port >= 0 AND port < 1 << 16),
    timestamp INT NOT NULL,
    FOREIGN KEY (ip, port) REFERENCES servers(ip, port)
) STRICT;

CREATE TABLE IF NOT EXISTS successful_legacy_pings (
    ip INT NOT NULL CHECK(ip >= 0 AND ip < 1 << 32),
    port INT NOT NULL CHECK(port >= 0 AND port < 1 << 16),
    timestamp INT NOT NULL,
    max_players INT NOT NULL,
    current_players INT NOT NULL,
    description TEXT NOT NULL,
    FOREIGN KEY (ip, port) REFERENCES servers(ip, port)
) STRICT;

CREATE TABLE IF NOT EXISTS failed_joins (
    ip INT NOT NULL CHECK(ip >= 0 AND ip < 1 << 32),
    port INT NOT NULL CHECK(port >= 0 AND port < 1 << 16),
    timestamp INT NOT NULL,
    FOREIGN KEY (ip, port) REFERENCES servers(ip, port)
) STRICT;

CREATE TABLE IF NOT EXISTS successful_joins (
    ip INT NOT NULL CHECK(ip >= 0 AND ip < 1 << 32),
    port INT NOT NULL CHECK(port >= 0 AND port < 1 << 16),
    timestamp INT NOT NULL,
    FOREIGN KEY (ip, port) REFERENCES servers(ip, port)
) STRICT;

CREATE TABLE IF NOT EXISTS players (
    uuid_low INT NOT NULL,
    uuid_high INT NOT NULL,
    name BLOB NOT NULL,
   PRIMARY KEY (uuid_high, uuid_low)
) STRICT;

CREATE TABLE IF NOT EXISTS ping_players (
    ping_id INT NOT NULL,
    player_uuid INT NOT NULL,
    PRIMARY KEY (ping_id, player_uuid),
    FOREIGN KEY (ping_id) REFERENCES successful_pings(_rowid_),
    FOREIGN KEY (player_uuid) REFERENCES players(uuid)
) STRICT;
