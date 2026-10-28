#!/usr/bin/env python3
"""Validate release translations and printf arguments before shipping."""
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
FORMAT = re.compile(r'%(?:\d+\$)?[-+0 #]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|ll|[hlLzjtq])?[@diuoxXfFeEgGaAcCsSp]')

def read(path):
    return json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(path)]))

def signature(value):
    return sorted(re.sub(r'^%\d+\$', '%', token) for token in FORMAT.findall(value.replace('%%', '')))

catalogs = {p.parent.stem: read(p) for p in (ROOT / 'Translations').glob('*.lproj/Localizable.strings')}
english = catalogs['en']
errors = []
for language, strings in catalogs.items():
    if language in ('en', 'zh-Hans', 'zh-Hant'):
        for key in english.keys() - strings.keys():
            errors.append(f'{language}: missing {key}')
    for key in english.keys() & strings.keys():
        if not strings[key].strip() or signature(strings[key]) != signature(english[key]):
            errors.append(f'{language}: invalid translation/arguments for {key}')
permissions = set()
for platform in ('iOS', 'tvOS'):
    info = read(ROOT / f'WatermelonFin {platform}/Resources/Info.plist')
    permissions.update(key for key in info if key.endswith('UsageDescription'))
    if info.get('CFBundleDevelopmentRegion') != 'en':
        errors.append(f'{platform}: development language must fall back to English')
for language in ('en', 'zh-Hans', 'zh-Hant'):
    strings = read(ROOT / f'Translations/{language}.lproj/InfoPlist.strings')
    for key in permissions:
        if not strings.get(key, '').strip():
            errors.append(f'{language}: missing permission {key}')
playlist = json.loads((ROOT / 'Translations/Playlist.xcstrings').read_text())
for key, entry in playlist['strings'].items():
    translations = entry.get('localizations', {})
    source = translations.get('en', {}).get('stringUnit', {}).get('value', '')
    for language in ('en', 'zh-Hans', 'zh-Hant'):
        value = translations.get(language, {}).get('stringUnit', {}).get('value', '')
        if not value or signature(value) != signature(source):
            errors.append(f'{language}: invalid playlist translation for {key}')
if errors:
    print('\n'.join(errors))
    raise SystemExit(1)
print(f'PASS: English and both Chinese catalogs complete; arguments valid across {len(catalogs)} languages; permissions localized')
