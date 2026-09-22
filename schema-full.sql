-- TimeTracker D1 schema. Paste into the D1 console once to create the tables.

CREATE TABLE IF NOT EXISTS users (
    id          TEXT PRIMARY KEY,      -- uuid
    email       TEXT UNIQUE NOT NULL,
    name        TEXT NOT NULL,
    password    TEXT NOT NULL,         -- pbkdf2$iterations$salt$hash
    role        TEXT NOT NULL DEFAULT 'user',  -- 'admin' | 'user'
    created_at  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS sessions (
    token       TEXT PRIMARY KEY,
    user_id     TEXT NOT NULL,
    expires_at  TEXT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id)
);
CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);

CREATE TABLE IF NOT EXISTS shifts (
    id          TEXT PRIMARY KEY,      -- uuid from the app
    user_id     TEXT NOT NULL,
    start_at    TEXT NOT NULL,
    end_at      TEXT,                  -- null while running
    FOREIGN KEY (user_id) REFERENCES users(id)
);
CREATE INDEX IF NOT EXISTS idx_shifts_user ON shifts(user_id, start_at);

CREATE TABLE IF NOT EXISTS minutes (
    id          TEXT PRIMARY KEY,      -- user_id + ':' + timestamp
    user_id     TEXT NOT NULL,
    ts          TEXT NOT NULL,
    keyboard    INTEGER NOT NULL,
    mouse       INTEGER NOT NULL,
    overall     INTEGER NOT NULL,
    apps        TEXT,                  -- JSON [{name,seconds,title}]
    screenshots TEXT,                  -- JSON [r2 keys]
    FOREIGN KEY (user_id) REFERENCES users(id)
);
CREATE INDEX IF NOT EXISTS idx_minutes_user ON minutes(user_id, ts);

CREATE TABLE IF NOT EXISTS warnings (
    id          TEXT PRIMARY KEY,
    user_id     TEXT NOT NULL,
    user_name   TEXT NOT NULL,
    started_at  TEXT NOT NULL,
    resolved_at TEXT,
    outcome     TEXT,                  -- 'resumed' | 'clockedOut'
    screenshot  TEXT,                  -- r2 key
    activity    INTEGER NOT NULL,
    app         TEXT,
    FOREIGN KEY (user_id) REFERENCES users(id)
);
CREATE INDEX IF NOT EXISTS idx_warnings_user ON warnings(user_id, started_at);
