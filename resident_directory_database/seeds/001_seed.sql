BEGIN;

-- Roles
INSERT INTO roles (name, description)
VALUES
  ('admin', 'Administrator with elevated permissions'),
  ('resident', 'Standard resident user')
ON CONFLICT (name) DO UPDATE
SET description = EXCLUDED.description;

-- Optional: Create a bootstrap admin account.
-- Password hash is a placeholder and MUST be replaced by the backend's password hashing strategy.
-- If you do not want a default admin, remove this section.
INSERT INTO users (email, password_hash, is_active, is_verified)
VALUES ('admin@example.com', 'CHANGE_ME_BACKEND_HASH', true, false)
ON CONFLICT (email) DO NOTHING;

-- Ensure bootstrap admin has admin role (if user exists).
INSERT INTO user_roles (user_id, role_id)
SELECT u.id, r.id
FROM users u
JOIN roles r ON r.name = 'admin'
WHERE u.email = 'admin@example.com'
ON CONFLICT DO NOTHING;

COMMIT;
