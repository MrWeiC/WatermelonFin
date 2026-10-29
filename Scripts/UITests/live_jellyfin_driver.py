#!/usr/bin/env python3
"""Loopback driver for live UI tests. Keychain credentials stay in this process.
Only Quick Connect authorization and read-only inspection are supported.
"""
import json
import subprocess
import uuid
import urllib.request
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

CONFIG = None
BASE = None
TOKEN = None
USER_ID = None
DEVICE_ID = str(uuid.uuid4())

def request(path, body=None):
    headers = {'Authorization': 'MediaBrowser Client="WatermelonFin UI Audit", Device="Simulator Audit", DeviceId="' + DEVICE_ID + '", Version="1"' + (f', Token="{TOKEN}"' if TOKEN else '')}
    if body is not None:
        headers['Content-Type'] = 'application/json'
    req = urllib.request.Request(BASE + '/' + path, data=json.dumps(body).encode() if body is not None else None, headers=headers)
    with urllib.request.urlopen(req, timeout=30) as response:
        data = response.read()
        return json.loads(data) if data else None

def authenticate():
    global TOKEN, USER_ID, CONFIG, BASE
    if CONFIG is None:
        CONFIG = json.loads((Path.home() / '.config/watermelonfin-mcp/connection.json').read_text())
    BASE = CONFIG['url'].rstrip('/')
    public = request('System/Info/Public')
    if public['Id'] != CONFIG['serverId']:
        raise RuntimeError('Server identity mismatch')
    password = subprocess.check_output(['security', 'find-generic-password', '-s', CONFIG['keychainService'], '-a', CONFIG['username'], '-w'], text=True).rstrip('\n')
    result = request('Users/AuthenticateByName', {'Username': CONFIG['username'], 'Pw': password})
    password = None
    TOKEN = result['AccessToken']
    me = request('Users/Me')
    policy = me['Policy']
    if policy.get('IsAdministrator') is not False:
        raise RuntimeError('Administrative account refused')
    if policy.get('EnableContentDeletion') is not False:
        raise RuntimeError('Deletion-enabled account refused')
    if policy.get('EnableContentDeletionFromFolders'):
        raise RuntimeError('Folder deletion permission refused')
    USER_ID = me['Id']
    print(json.dumps({'authenticated': True, 'administrator': False, 'contentDeletion': False, 'folderDeletion': False}), flush=True)

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.headers.get('Origin'):
            self.send_error(403); return
        try:
            if self.path == '/configuration':
                value = {'serverURL': BASE, 'restricted': True}
            elif self.path == '/inventory':
                query = urllib.parse.urlencode({'UserId': USER_ID, 'Recursive': 'true', 'IncludeItemTypes': 'Movie,Episode', 'Limit': 100, 'Fields': 'MediaStreams,MediaSources'})
                items = request('Items?' + query).get('Items', [])
                value = [{'id': i['Id'], 'name': i.get('Name'), 'type': i.get('Type'), 'durationSeconds': i.get('RunTimeTicks', 0)/10000000, 'streams': [{'type': s.get('Type'), 'codec': s.get('Codec'), 'language': s.get('Language')} for s in i.get('MediaStreams', [])]} for i in items]
            elif self.path == '/sessions':
                sessions = request('Sessions')
                value = [{'client': s.get('Client'), 'device': s.get('DeviceName'), 'itemId': s.get('NowPlayingItem', {}).get('Id'), 'positionTicks': s.get('PlayState', {}).get('PositionTicks'), 'paused': s.get('PlayState', {}).get('IsPaused'), 'playMethod': s.get('PlayState', {}).get('PlayMethod'), 'audioIndex': s.get('PlayState', {}).get('AudioStreamIndex'), 'subtitleIndex': s.get('PlayState', {}).get('SubtitleStreamIndex')} for s in sessions if s.get('UserId') == USER_ID]
            else:
                self.send_error(404); return
            self.respond(value)
        except Exception as error:
            self.send_error(502, type(error).__name__)
    def do_POST(self):
        if self.headers.get('Origin') or self.headers.get_content_type() != 'application/json':
            self.send_error(403); return
        if self.path != '/authorize':
            self.send_error(404); return
        try:
            body = json.loads(self.rfile.read(min(int(self.headers.get('Content-Length', 0)), 1024)))
            code = body.get('code', '')
            if not isinstance(code, str) or len(code) != 6 or not code.isdigit():
                raise ValueError('Invalid Quick Connect code')
            result = request('QuickConnect/Authorize?Code=' + code, {})
            self.respond({'authorized': result is True})
        except Exception as error:
            self.send_error(502, type(error).__name__)
    def respond(self, value):
        data = json.dumps(value).encode(); self.send_response(200)
        self.send_header('Content-Type', 'application/json'); self.send_header('Content-Length', str(len(data))); self.end_headers(); self.wfile.write(data)
    def log_message(self, *args):
        pass

if __name__ == '__main__':
    authenticate()
    ThreadingHTTPServer(('127.0.0.1', 18097), Handler).serve_forever()
