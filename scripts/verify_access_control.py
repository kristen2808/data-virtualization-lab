"""Interactive ACL checks; passwords stay in memory and are never printed."""
import base64
import getpass
import json
from pathlib import Path
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[1]
BASE = 'https://localhost:8443'
CONTEXT = ssl.create_default_context(cafile=str(ROOT / 'secrets/trino/localhost.crt'))
TOKENS = {}
FAILURES = []


def request(user, path, data=None, method=None):
    url = urllib.parse.urljoin(BASE, path)
    if urllib.parse.urlsplit(url).netloc != 'localhost:8443' or not url.startswith(BASE + '/'):
        raise RuntimeError('Refusing to send credentials to another endpoint')
    req = urllib.request.Request(url, data=data, method=method, headers={
        'Authorization': 'Basic ' + TOKENS[user], 'X-Trino-User': user,
    })
    try:
        with urllib.request.urlopen(req, context=CONTEXT, timeout=30) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


def sql(user, statement):
    status, body = request(user, '/v1/statement', statement.encode())
    if status != 200:
        raise RuntimeError(f'{user}: HTTP {status}')
    result = json.loads(body)
    query_id = result['id']
    rows = []
    while True:
        if 'error' in result:
            return rows, result['error'], query_id
        rows.extend(result.get('data', []))
        if 'nextUri' not in result:
            return rows, None, query_id
        status, body = request(user, result['nextUri'])
        if status != 200:
            raise RuntimeError(f'{user}: result HTTP {status}')
        result = json.loads(body)


def record(label, passed, detail=''):
    print(('PASS ' if passed else 'FAIL ') + label + (': ' + detail if detail else ''))
    if not passed:
        FAILURES.append(label)


def check(user, statement, denied=False):
    rows, error, query_id = sql(user, statement)
    permission_denied = error and error.get('errorName') == 'PERMISSION_DENIED'
    passed = bool(permission_denied) if denied else error is None
    detail = error.get('errorName', 'UNKNOWN') if error else ''
    record(f'{user}: {statement}', passed, detail)
    return rows, query_id, passed


def main():
    for user in ('admin', 'analyst'):
        password = getpass.getpass(f'Trino password for {user}: ')
        TOKENS[user] = base64.b64encode((user + ':' + password).encode()).decode()
        del password
    for user in TOKENS:
        rows, _, ok = check(user, 'SELECT current_user')
        if not ok or rows != [[user]]:
            raise RuntimeError('Identity verification failed; no test tables created')
    for user in TOKENS:
        rows, _, _ = check(user, 'SHOW CATALOGS')
        names = {row[0] for row in rows}
        record(user + ': pg_lab visible', 'pg_lab' in names)
        if user == 'analyst':
            record('analyst: catalog allowlist', names == {'pg_lab', 'mssql_lab', 'system'})
        check(user, 'SHOW SCHEMAS FROM pg_lab')
        check(user, 'SHOW TABLES FROM pg_lab.public')
        check(user, 'SELECT * FROM system.jdbc.catalogs')
    check('admin', 'SELECT * FROM system.runtime.nodes')
    check('analyst', 'SELECT * FROM system.runtime.nodes', denied=True)
    check('analyst', 'SELECT * FROM tpch.sf1.nation', denied=True)
    check('analyst', "SELECT * FROM TABLE(pg_lab.system.query(query => 'SELECT 1'))", denied=True)
    check('analyst', "CALL pg_lab.system.execute(query => 'SELECT 1')", denied=True)
    # Exercise query-owner checks independently of SQL procedure permissions.
    _, query_id, _ = check('admin', 'SELECT 1')
    status, _ = request('admin', '/v1/query/' + query_id)
    record('admin: view query REST endpoint', status == 200, f'HTTP {status}')
    status, _ = request('analyst', '/v1/query/' + query_id)
    record('analyst: cannot view admin query', status == 403, f'HTTP {status}')
    status, _ = request('analyst', '/v1/query/' + query_id, method='DELETE')
    record('analyst: cannot kill admin query', status == 403, f'HTTP {status}')
    _, analyst_query, _ = check('analyst', 'SELECT 1')
    status, _ = request('analyst', '/v1/query/' + analyst_query)
    record('analyst: view own query', status == 200, f'HTTP {status}')
    status, _ = request('admin', '/v1/query/' + analyst_query)
    record('admin: view analyst query', status == 200, f'HTTP {status}')
    status, _ = request('admin', '/v1/query/' + analyst_query, method='DELETE')
    record('admin: kill analyst query (completed query authorization)', status == 204, f'HTTP {status}')
    _, own_query, _ = check('analyst', 'SELECT 1')
    status, _ = request('analyst', '/v1/query/' + own_query, method='DELETE')
    record('analyst: kill own query (completed query authorization)', status == 204, f'HTTP {status}')
    # Fresh unpredictable names only; cleanup never targets pre-existing tables.
    suffix = uuid.uuid4().hex
    table = 'pg_lab.public.acl_probe_' + suffix
    other = table + '_analyst'
    created = False
    try:
        _, _, created = check('admin', f'CREATE TABLE {table} (id bigint)')
        if not created:
            return
        check('admin', f'INSERT INTO {table} VALUES (1)')
        check('admin', f'SELECT * FROM {table}')
        check('analyst', f'SELECT * FROM {table}')
        check('analyst', f'INSERT INTO {table} VALUES (2)', denied=True)
        check('analyst', f'UPDATE {table} SET id = 2 WHERE id = 1', denied=True)
        check('analyst', f'DELETE FROM {table} WHERE id = 1', denied=True)
        check('analyst', f'CREATE TABLE {other} (id bigint)', denied=True)
        check('analyst', f'DROP TABLE {table}', denied=True)
        check('admin', f'UPDATE {table} SET id = 3 WHERE id = 1')
        check('admin', f'DELETE FROM {table} WHERE id = 3')
    finally:
        if created:
            check('admin', f'DROP TABLE IF EXISTS {table}')
            check('admin', f'DROP TABLE IF EXISTS {other}')


if __name__ == '__main__':
    try:
        main()
    except (Exception, KeyboardInterrupt) as error:
        # Do not print exception bodies, headers, or credential-bearing objects.
        print('FAIL test interrupted or failed: ' + type(error).__name__)
        FAILURES.append('execution')
    finally:
        TOKENS.clear()
    print(f'Failures: {len(FAILURES)}')
    sys.exit(1 if FAILURES else 0)
