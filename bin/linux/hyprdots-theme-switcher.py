#!/usr/bin/env python3
"""Use Omarchy's theme previews with the personal hidden-theme list."""

import argparse
import hashlib
import os
from pathlib import Path
import re
import subprocess


def prepare_previews(cache, hidden_file):
    hidden = set()
    for line in hidden_file.read_text().splitlines():
        slug = line.strip()
        if not slug or slug.startswith('#'):
            continue
        if not re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*', slug):
            raise ValueError(f'Invalid hidden theme slug: {slug}')
        hidden.add(slug)

    source = cache / 'omarchy/theme-selector/previews'
    previews = cache / 'hyprdots/theme-selector/previews'
    previews.mkdir(parents=True, exist_ok=True)
    visible = {}
    for preview in source.iterdir():
        if (preview.stem not in hidden and preview.is_file()
                and preview.suffix.lower() in {'.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp'}):
            visible[preview.name] = preview.resolve()

    for old in previews.iterdir():
        if old.name not in visible or old.resolve() != visible[old.name]:
            old.unlink()
    for name, target in visible.items():
        link = previews / name
        if not link.is_symlink():
            link.symlink_to(target)

    # Omarchy's row fast-cache only checks directory mtimes to the second.
    # Invalidate our view's rows so same-second renames and content changes
    # cannot leave a hidden theme or an old preview in the menu.
    key = hashlib.md5(os.fsencode(previews)).hexdigest()
    for suffix in ('rows', 'signature', 'fast-signature'):
        (cache / f'omarchy/image-selector/{key}.{suffix}').unlink(missing_ok=True)
    return previews


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--preload', action='store_true')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    cache = Path(os.environ.get('XDG_CACHE_HOME', Path.home() / '.cache'))
    # Reuse the packaged preview discovery; it knows user/stock precedence.
    subprocess.run(['omarchy', 'theme', 'switcher', '--preload'], check=True,
                   stdout=subprocess.DEVNULL)
    previews = prepare_previews(cache, repo / 'config/hidden-themes.txt')
    current_file = Path.home() / '.local/state/omarchy/current/theme.name'
    current = current_file.read_text().strip() if current_file.exists() else ''
    selected = next((str(p) for p in sorted(previews.iterdir()) if p.stem == current), '')
    command = ['omarchy-menu-images', '--print-name', '--show-labels', '--filterable',
               '--lazy-thumbnails', '--selected', selected]
    if args.preload:
        command.append('--preload')
    command.append(str(previews))
    os.execvp(command[0], command)


if __name__ == '__main__':
    main()
