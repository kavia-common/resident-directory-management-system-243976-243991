-- Resident Directory App - Initial Schema
-- This migration is intended to be idempotent (safe to run multiple times).
-- It creates core tables for:
-- - users/roles
-- - profiles + privacy
-- - announcements
-- - contact requests + messaging
-- - import/export tracking
-- - audit logs
--
-- NOTE: This repository's database container uses db_connection.txt as the canonical connection string.

BEGIN;

-- Extensions (safe if already installed)
CREATE EXTENSION IF NOT EXISTS pgcrypto; -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS citext;   -- case-insensitive email

-- =========================
-- Auth / Users / Roles
-- =========================

CREATE TABLE IF NOT EXISTS roles (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL UNIQUE,
    description text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS users (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    email citext NOT NULL UNIQUE,
    password_hash text NOT NULL,
    is_active boolean NOT NULL DEFAULT true,
    is_verified boolean NOT NULL DEFAULT false,
    last_login_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

CREATE TABLE IF NOT EXISTS user_roles (
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id uuid NOT NULL REFERENCES roles(id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, role_id)
);

-- =========================
-- Profiles + Privacy
-- =========================

-- Profile fields are meant to support a searchable directory.
-- Privacy fields control whether attributes are shown in directory listings.
CREATE TABLE IF NOT EXISTS resident_profiles (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,

    -- core identity
    first_name text NOT NULL,
    last_name text NOT NULL,
    display_name text,
    unit text,                 -- apartment/unit number (optional)
    building text,             -- building name/identifier (optional)

    -- optional directory fields
    phone text,
    email_public_override citext, -- optional public-facing email if different

    -- free-form
    bio text,

    -- tags for searching/filtering (e.g., "board-member", "dog-owner")
    tags text[] NOT NULL DEFAULT ARRAY[]::text[],

    -- privacy controls
    is_directory_visible boolean NOT NULL DEFAULT true,
    show_email boolean NOT NULL DEFAULT false,
    show_phone boolean NOT NULL DEFAULT false,
    show_unit boolean NOT NULL DEFAULT false,
    show_building boolean NOT NULL DEFAULT false,
    show_bio boolean NOT NULL DEFAULT true,
    show_tags boolean NOT NULL DEFAULT true,

    -- timestamps
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_profiles_name ON resident_profiles(last_name, first_name);
CREATE INDEX IF NOT EXISTS idx_profiles_unit ON resident_profiles(unit);
CREATE INDEX IF NOT EXISTS idx_profiles_building ON resident_profiles(building);
CREATE INDEX IF NOT EXISTS idx_profiles_visible ON resident_profiles(is_directory_visible);

-- GIN index for tags filtering
CREATE INDEX IF NOT EXISTS idx_profiles_tags_gin ON resident_profiles USING GIN(tags);

-- =========================
-- Announcements
-- =========================

CREATE TABLE IF NOT EXISTS announcements (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    title text NOT NULL,
    body text NOT NULL,
    created_by_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
    is_published boolean NOT NULL DEFAULT true,
    published_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_announcements_published ON announcements(is_published, published_at DESC, created_at DESC);

-- =========================
-- Contact Requests / Messaging
-- =========================

-- A "contact request" is a lightweight workflow for residents to reach out,
-- optionally escalating into a message thread.
CREATE TABLE IF NOT EXISTS contact_requests (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    from_user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    to_user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    subject text,
    initial_message text NOT NULL,

    status text NOT NULL DEFAULT 'pending', -- pending|accepted|declined|cancelled|closed
    responded_at timestamptz,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_contact_requests_status
        CHECK (status IN ('pending','accepted','declined','cancelled','closed')),

    CONSTRAINT uq_contact_request_open
        UNIQUE (from_user_id, to_user_id, status)
);

-- Note: uq_contact_request_open is imperfect because it prevents multiple rows with same status,
-- but it blocks spamming "pending" duplicates. Backend can relax/remove later if needed.

CREATE INDEX IF NOT EXISTS idx_contact_requests_to_status ON contact_requests(to_user_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_contact_requests_from_status ON contact_requests(from_user_id, status, created_at DESC);

-- Message threads are optional; can be created on acceptance of a contact request.
CREATE TABLE IF NOT EXISTS message_threads (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    created_by_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
    contact_request_id uuid UNIQUE REFERENCES contact_requests(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS message_thread_participants (
    thread_id uuid NOT NULL REFERENCES message_threads(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (thread_id, user_id)
);

CREATE TABLE IF NOT EXISTS messages (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    thread_id uuid NOT NULL REFERENCES message_threads(id) ON DELETE CASCADE,
    sender_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
    body text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_messages_thread_created ON messages(thread_id, created_at ASC);

-- =========================
-- Import/Export Tracking
-- =========================

CREATE TABLE IF NOT EXISTS data_import_jobs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    requested_by_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
    source text NOT NULL DEFAULT 'admin_ui', -- admin_ui|api|other
    status text NOT NULL DEFAULT 'queued', -- queued|running|succeeded|failed|cancelled
    total_records integer NOT NULL DEFAULT 0,
    processed_records integer NOT NULL DEFAULT 0,
    error_count integer NOT NULL DEFAULT 0,
    error_summary text,
    created_at timestamptz NOT NULL DEFAULT now(),
    started_at timestamptz,
    finished_at timestamptz,

    CONSTRAINT chk_import_status
        CHECK (status IN ('queued','running','succeeded','failed','cancelled'))
);

CREATE TABLE IF NOT EXISTS data_export_jobs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    requested_by_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
    format text NOT NULL DEFAULT 'csv', -- csv|json
    status text NOT NULL DEFAULT 'queued', -- queued|running|succeeded|failed|cancelled
    total_records integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    started_at timestamptz,
    finished_at timestamptz,
    error_summary text,

    CONSTRAINT chk_export_status
        CHECK (status IN ('queued','running','succeeded','failed','cancelled')),

    CONSTRAINT chk_export_format
        CHECK (format IN ('csv','json'))
);

-- =========================
-- Audit Logs
-- =========================

-- Generic audit log capturing who did what and when.
-- Backend can store request_id / ip / user_agent as needed.
CREATE TABLE IF NOT EXISTS audit_logs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_user_id uuid REFERENCES users(id) ON DELETE SET NULL,

    action text NOT NULL,          -- e.g. "user.login", "profile.update", "announcement.create"
    entity_type text,              -- e.g. "resident_profile"
    entity_id uuid,                -- referenced entity (optional)
    success boolean NOT NULL DEFAULT true,

    -- metadata
    request_id text,
    ip_address text,
    user_agent text,

    -- store payload diffs/extra context; jsonb keeps it flexible
    details jsonb NOT NULL DEFAULT '{}'::jsonb,

    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_created ON audit_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_actor_created ON audit_logs(actor_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity ON audit_logs(entity_type, entity_id);

-- =========================
-- Trigger helpers for updated_at
-- =========================

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_users_updated_at') THEN
    CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_profiles_updated_at') THEN
    CREATE TRIGGER trg_profiles_updated_at
    BEFORE UPDATE ON resident_profiles
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_announcements_updated_at') THEN
    CREATE TRIGGER trg_announcements_updated_at
    BEFORE UPDATE ON announcements
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_contact_requests_updated_at') THEN
    CREATE TRIGGER trg_contact_requests_updated_at
    BEFORE UPDATE ON contact_requests
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
  END IF;
END;
$$;

COMMIT;
