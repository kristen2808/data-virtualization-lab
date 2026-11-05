-- PostgreSQL 17 / psql script, not plain SQL for DBeaver.
-- Connect as lab_user to the maintenance database postgres.
-- Run with psql -X -f; never use --single-transaction (-1).
-- New role password: optional SUPERSET_DB_PASSWORD environment variable
-- (plaintext or PostgreSQL SCRAM verifier); otherwise a hidden \password prompt.
-- Existing role passwords are never changed by this script.
\set ON_ERROR_STOP on
\set ECHO none
\set ECHO_HIDDEN off
\set AUTOCOMMIT on

SELECT pg_advisory_lock(2026, 485);

DO $check$
BEGIN
    IF current_database() <> 'postgres' OR current_user <> 'lab_user' THEN
        RAISE EXCEPTION 'Connect as lab_user to the postgres maintenance database';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname=current_user
                   AND rolsuper AND rolcreatedb AND rolcreaterole) THEN
        RAISE EXCEPTION 'lab_user must have SUPERUSER, CREATEDB and CREATEROLE';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='superset'
               AND (NOT rolcanlogin OR rolsuper OR rolcreatedb OR rolcreaterole
                    OR rolreplication OR rolbypassrls))
       OR EXISTS (SELECT 1 FROM pg_auth_members
                  WHERE member=(SELECT oid FROM pg_roles WHERE rolname='superset')) THEN
        RAISE EXCEPTION 'Existing superset role has incompatible privileges or memberships; no automatic repair';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_database WHERE datname='superset_metadata'
               AND (pg_get_userbyid(datdba)<>'superset' OR NOT datallowconn
                    OR datistemplate OR pg_encoding_to_char(encoding)<>'UTF8')) THEN
        RAISE EXCEPTION 'Existing superset_metadata database has incompatible owner/settings; left unchanged';
    END IF;
END
$check$;

SELECT NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='superset') AS create_role
\gset

\if :create_role
    BEGIN;
    SET LOCAL password_encryption='scram-sha-256';
    CREATE ROLE superset WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
        NOREPLICATION NOBYPASSRLS NOINHERIT;
    \getenv superset_password SUPERSET_DB_PASSWORD
    \if :{?superset_password}
        SELECT length(:'superset_password') > 0 AS nonempty_password
        \gset
        \if :nonempty_password
            SELECT format('ALTER ROLE superset PASSWORD %L', :'superset_password')
            \gexec
        \else
            DO $error$ BEGIN RAISE EXCEPTION 'SUPERSET_DB_PASSWORD must not be empty'; END $error$;
        \endif
        \unset superset_password
    \else
        \password superset
    \endif
    DO $password_check$
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM pg_authid WHERE rolname='superset'
                       AND rolpassword LIKE 'SCRAM-SHA-256$%') THEN
            RAISE EXCEPTION 'A SCRAM password is required; new role creation rolled back';
        END IF;
    END
    $password_check$;
    COMMIT;
\else
    \echo 'Existing superset role preserved; password unchanged.'
\endif

-- CREATE DATABASE is not allowed inside a transaction. Only a missing database
-- is created. Role creation may remain committed if database creation fails.
SELECT 'CREATE DATABASE superset_metadata OWNER superset TEMPLATE template0 ENCODING ''UTF8'''
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname='superset_metadata')
\gexec

DO $verify$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='superset'
                   AND rolcanlogin AND NOT rolsuper AND NOT rolcreatedb
                   AND NOT rolcreaterole AND NOT rolreplication AND NOT rolbypassrls)
       OR NOT EXISTS (SELECT 1 FROM pg_authid WHERE rolname='superset' AND rolpassword IS NOT NULL)
       OR NOT EXISTS (SELECT 1 FROM pg_database WHERE datname='superset_metadata'
                      AND pg_get_userbyid(datdba)='superset' AND datallowconn) THEN
        RAISE EXCEPTION 'Superset metadata database or role verification failed';
    END IF;
END
$verify$;

SELECT rolname, rolcanlogin, rolsuper, rolcreatedb, rolcreaterole
FROM pg_roles WHERE rolname='superset';
SELECT datname, pg_get_userbyid(datdba) AS owner
FROM pg_database WHERE datname='superset_metadata';
SELECT pg_advisory_unlock(2026, 485);
