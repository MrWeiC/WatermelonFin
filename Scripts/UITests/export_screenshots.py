#!/usr/bin/env python3
"""Export named XCTest screenshots from a result bundle into a report directory."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('result_bundle', type=Path)
parser.add_argument('output', type=Path)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='watermelon-screenshots-') as temp:
    subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path',
                    str(args.result_bundle), '--output-path', temp], check=True)
    root = Path(temp)
    manifest = json.loads((root / 'manifest.json').read_text())
    seen = set()
    for test in manifest:
        for item in test['attachments']:
            source = root / item['exportedFileName']
            if source.suffix.lower() != '.png':
                continue
            name = item['suggestedHumanReadableName'].split('_0_')[0] + '.png'
            if name in seen:
                raise ValueError(f'Duplicate screenshot name: {name}; export one device per bundle')
            seen.add(name)
            shutil.copyfile(source, args.output / name)
    (args.output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
