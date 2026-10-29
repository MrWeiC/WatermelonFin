#!/usr/bin/env python3
"""Loopback-only Jellyfin fixture for real-app UI automation.

Use http://127.0.0.1:18096/<scenario>/<unique-run-id> as the server URL.
Scenarios: users, empty, disabled, slow, slow-login, spaced-password, unavailable, quick-error, quick-retry.
Never accepts or forwards real credentials. Each run ID has a distinct server ID.
"""
import argparse
import hashlib
import json
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse


class Handler(BaseHTTPRequestHandler):
    attempts = {}
    def respond(self, status, value):
        body = json.dumps(value).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass  # Cancellation is a test scenario.

    def request(self):
        parts = urlparse(self.path).path.strip('/').split('/')
        scenario, run = (parts + ['users', 'default'])[:2]
        endpoint = '/'.join(parts[2:]).lower()
        if endpoint == 'quickconnect/initiate' and self.command != 'POST':
            return self.respond(405, {'Message': 'Quick Connect initiation requires POST'})
        server_id = hashlib.md5(run.encode()).hexdigest()
        user = {'Id': hashlib.md5((run + 'user').encode()).hexdigest(),
                'Name': 'Preview User', 'ServerId': server_id,
                'HasPassword': True, 'Policy': {'IsAdministrator': False,
                    'AuthenticationProviderId': 'fixture', 'PasswordResetProviderId': 'fixture'}}
        if scenario == 'unavailable':
            return self.respond(503, {'Message': 'Fixture server unavailable'})
        if scenario == 'slow':
            time.sleep(6)
        if endpoint == 'system/info/public':
            value = {'ServerName': 'Preview Media Server', 'Id': server_id,
                     'Version': '10.11.0', 'StartupWizardCompleted': True}
        elif endpoint == 'users/public':
            value = [] if scenario == 'empty' else [user]
        elif endpoint == 'quickconnect/enabled':
            value = scenario != 'disabled'
        elif endpoint in ('quickconnect/initiate', 'quickconnect/connect'):
            key = (run, endpoint)
            self.attempts[key] = self.attempts.get(key, 0) + 1
            if scenario == 'quick-error' or (scenario == 'quick-retry' and endpoint == 'quickconnect/initiate' and self.attempts[key] == 1):
                return self.respond(503, {'Message': 'Quick Connect unavailable'})
            value = {'Code': '123456', 'Secret': 'fixture-only-secret', 'Authenticated': scenario == 'quick-retry'}
        elif endpoint == 'users/authenticatewithquickconnect':
            value = {'User': user, 'AccessToken': 'fixture-only-token', 'ServerId': server_id}
        elif endpoint == 'users/authenticatebyname':
            payload = json.loads(self.rfile.read(int(self.headers.get('Content-Length', 0))) or '{}')
            if scenario == 'slow-login':
                time.sleep(6)
            expected = ' fixture-password ' if scenario == 'spaced-password' else 'fixture-password'
            if payload.get('Pw') != expected:
                return self.respond(401, {'Message': 'Invalid username or password'})
            value = {'User': user, 'AccessToken': 'fixture-only-token', 'ServerId': server_id}
        elif endpoint.startswith('users/') and endpoint.count('/') == 1:
            value = user
        elif endpoint.endswith(('items', 'views', 'resume')):
            value = {'Items': [], 'TotalRecordCount': 0, 'StartIndex': 0}
        elif endpoint.endswith('latest'):
            value = []
        else:
            value = {}
        self.respond(200, value)

    do_GET = request
    do_POST = request

    def log_message(self, format, *args):
        # Paths only: never log authorization headers or request bodies.
        print(format % args, flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=18096)
    args = parser.parse_args()
    ThreadingHTTPServer(('127.0.0.1', args.port), Handler).serve_forever()
