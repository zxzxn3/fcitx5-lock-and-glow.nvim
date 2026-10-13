#!/usr/bin/env python3
"""Copy the shared core from a dotfiles module directory; never replace state.lua."""
import argparse
import shutil
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('source', type=Path, help='Directory containing cursor.lua and lock.lua')
args = parser.parse_args()
source = args.source.expanduser().resolve()
destination = Path(__file__).resolve().parents[1] / 'lua' / 'fcitx5-ime'
for name in ('cursor.lua', 'lock.lua'):
    if not (source / name).is_file():
        parser.error(f'missing source file: {source / name}')
for name in ('cursor.lua', 'lock.lua'):
    shutil.copyfile(source / name, destination / name)
    print(f'Copied {name}')
