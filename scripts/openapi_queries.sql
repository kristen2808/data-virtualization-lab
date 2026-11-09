-- Execute individual read-only statements in Trino as admin or analyst.
-- Double quotes are required because the catalog name contains a hyphen.
SHOW TABLES FROM "open-api".default;

SELECT id, name, username, email
FROM "open-api".default.users
ORDER BY id;

SELECT id, user_id, title
FROM "open-api".default.posts
ORDER BY id
LIMIT 10;

-- Both endpoints belong to the same API and share its user ID domain.
SELECT u.id, u.name, count(p.id) AS post_count
FROM "open-api".default.users u
LEFT JOIN "open-api".default.posts p ON p.user_id = u.id
GROUP BY u.id, u.name
ORDER BY u.id;
