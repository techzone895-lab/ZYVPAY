CREATE TABLE IF NOT EXISTS devices (
  sid            TEXT PRIMARY KEY,
  phone          TEXT NOT NULL,
  pin_key        BYTEA NOT NULL,
  reg_code       TEXT NOT NULL,
  verified       BOOLEAN NOT NULL DEFAULT FALSE,
  last_ctr       BIGINT NOT NULL DEFAULT 0,
  failed_macs    INT NOT NULL DEFAULT 0,
  locked         BOOLEAN NOT NULL DEFAULT FALSE,
  balance_paise  BIGINT NOT NULL DEFAULT 0 CHECK (balance_paise >= 0),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS devices_phone_idx ON devices (phone);

CREATE TABLE IF NOT EXISTS payments (
  id            BIGSERIAL PRIMARY KEY,
  sid           TEXT NOT NULL REFERENCES devices(sid),
  ctr           BIGINT NOT NULL,
  amount_paise  BIGINT NOT NULL CHECK (amount_paise > 0),
  vpa           TEXT NOT NULL,
  channel       TEXT NOT NULL CHECK (channel IN ('sms', 'net')),
  status        TEXT NOT NULL CHECK (status IN ('processing', 'pending', 'success', 'failed')),
  ref           TEXT NOT NULL UNIQUE,
  payout_ref    TEXT,
  fail_reason   TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (sid, ctr)
);

-- Every balance change is recorded here; devices.balance_paise is the running total.
CREATE TABLE IF NOT EXISTS ledger (
  id           BIGSERIAL PRIMARY KEY,
  sid          TEXT NOT NULL REFERENCES devices(sid),
  delta_paise  BIGINT NOT NULL,
  reason       TEXT NOT NULL,
  payment_id   BIGINT REFERENCES payments(id),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS sms_outbox (
  id          BIGSERIAL PRIMARY KEY,
  to_phone    TEXT NOT NULL,
  body        TEXT NOT NULL,
  status      TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'sending', 'sent', 'failed')),
  attempts    INT NOT NULL DEFAULT 0,
  lease_until TIMESTAMPTZ,
  error       TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS sms_outbox_status_idx ON sms_outbox (status, id);

CREATE TABLE IF NOT EXISTS sms_inbox (
  id          BIGSERIAL PRIMARY KEY,
  from_phone  TEXT NOT NULL,
  body        TEXT NOT NULL,
  result      TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
