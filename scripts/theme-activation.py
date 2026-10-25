#!/usr/bin/env python3
"""Refresh managed Omarchy themes after Hyprdots has reconciled their sources."""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


IMAGE_SUFFIXES = {'.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'}
PREVIEW_NAMES = ('preview.png', 'preview.jpg', 'preview.jpeg', 'preview.webp',
                 'preview.gif', 'preview.bmp')
# Mirror Omarchy's exclusions only when checking its output. Omarchy remains
# responsible for staging/filtering; Hyprdots never copies executable overrides.
COMMUNITY_EXCLUSIONS = {'alacritty.toml', 'foot.ini', 'ghostty.conf', 'kitty.conf', 'vscode.json'}


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def file_digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def tree_digest(directory):
    """Include generated active files, without traversing directory symlinks."""
    if not directory.is_dir():
        return None
    entries = []
    for path in sorted(directory.rglob('*')):
        name = str(path.relative_to(directory))
        if path.is_symlink():
            entries.append((name, 'link', str(path.readlink()),
                            file_digest(path) if path.is_file() else None))
        elif path.is_file():
            entries.append((name, 'file', file_digest(path)))
    return digest(entries)


def read_receipt(path):
    try:
        data = json.loads(path.read_text())
        return data if isinstance(data, dict) and data.get('version') == 1 else {}
    except (FileNotFoundError, ValueError):
        return {}


def write_receipt(path, **values):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        json.dump(dict(version=1, **values), stream, sort_keys=True)
        stream.write('\n')
    try:
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def command(args, *, extra_env=None, timeout=120):
    result = subprocess.run(args, env=dict(os.environ, **(extra_env or {})),
                            capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        detail = (result.stderr or result.stdout).strip()
        raise RuntimeError(f"{' '.join(map(str, args))} failed ({result.returncode}): {detail}")
    return result.stdout


class ThemeActivation:
    def __init__(self, user_home, lock, omarchy_root, cache_home, run=command):
        self.user_home, self.omarchy_root, self.run = user_home, omarchy_root, run
        self.themes = user_home / '.config/omarchy/themes'
        self.current = user_home / '.local/state/omarchy/current'
        self.state = user_home / '.local/state/hyprdots/themes'
        self.cache = cache_home / 'omarchy'
        self.active_receipt = self.state / 'active.json'
        self.preview_receipt = self.state / 'previews.json'
        self.entries = {}
        for line in lock.read_text().splitlines():
            if not line or line.startswith('#'):
                continue
            fields = line.split('\t')
            if len(fields) != 5:
                raise ValueError('Invalid theme lock entry')
            slug, source, repository, revision, subdirectory = fields
            if (not re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*', slug)
                    or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', source)
                    or '..' in source or slug in self.entries
                    or not re.fullmatch(r'[0-9a-f]{40}', revision)
                    or not re.fullmatch(r'[A-Za-z0-9._/-]+', subdirectory)
                    or subdirectory.startswith('/') or '..' in subdirectory
                    or '//' in subdirectory or (subdirectory == '.' and source != slug)):
                raise ValueError(f'Invalid theme lock entry: {slug}')
            self.entries[slug] = (source, repository, revision, subdirectory)

    def selected(self):
        try:
            return (self.current / 'theme.name').read_text().strip()
        except FileNotFoundError:
            return ''

    def source_stamp(self, slug):
        source, repository, revision, subdirectory = self.entries[slug]
        checkout = (self.themes / slug if subdirectory == '.' else
                    self.user_home / '.local/share/hyprdots/theme-sources' / source)
        # A sibling edit moves the shared commit but not this theme's Git tree.
        installed, tree = self.run(['git', '-C', str(checkout), 'rev-parse', 'HEAD',
                                    f'{revision}^{{tree}}' if subdirectory == '.' else
                                    f'{revision}:{subdirectory}']).splitlines()
        if installed != revision:
            raise RuntimeError(f'Installed theme revision drifted: {slug}; run ./themes.sh sync')
        return digest((repository, subdirectory, tree))

    def active_stamp(self, slug):
        return digest((self.source_stamp(slug),
                       tree_digest(self.omarchy_root / 'themes' / slug),
                       tree_digest(self.omarchy_root / 'default/themed'),
                       tree_digest(self.user_home / '.config/omarchy/themed')))

    def background(self):
        link = self.current / 'background'
        if not link.is_symlink():
            return None
        # Keep the logical path through current/theme: activation replaces its
        # contents, and a surviving filename should keep the user's selection.
        return Path(os.path.abspath(link.parent / link.readlink()))

    def active_status(self, slug, desired):
        receipt = read_receipt(self.active_receipt)
        if receipt.get('slug') != slug:
            return 'unverified'
        if receipt.get('source') != desired:
            return 'stale source'
        if (not (self.current / 'theme/colors.toml').is_file()
                or receipt.get('contents') != tree_digest(self.current / 'theme')):
            return 'stale active files'
        background = self.background()
        if background is None or not background.is_file():
            return 'missing wallpaper'
        return 'current'

    def expected_preview(self, slug):
        directory = self.themes / slug
        files = sorted(directory.iterdir())
        for name in PREVIEW_NAMES:
            for path in files:
                if path.name.lower() == name and path.is_file():
                    return path
        backgrounds = self.images(directory / 'backgrounds')
        if not backgrounds:
            raise RuntimeError(f'No preview or wallpaper for managed theme: {slug}')
        return backgrounds[0]

    @staticmethod
    def images(directory):
        return sorted(path for path in directory.glob('*')
                      if path.suffix.lower() in IMAGE_SUFFIXES and path.is_file())

    def previews_match(self):
        for slug in self.entries:
            preview = self.expected_preview(slug)
            cached = self.cache / 'theme-selector/previews' / f'{slug}{preview.suffix.lower()}'
            if not cached.is_file() or cached.resolve() != preview.resolve():
                return False
        return True

    def previews_current(self, desired):
        return not self.entries or (read_receipt(self.preview_receipt).get('sources') == desired
                and self.previews_match())

    def desktop_ready(self):
        try:
            self.run(['omarchy-shell', 'shell', 'ping'], timeout=3)
            monitors = json.loads(self.run(['hyprctl', '-j', 'monitors'], timeout=3))
            return isinstance(monitors, list) and bool(monitors)
        except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired):
            return False

    def verify_applied(self, slug):
        """Check supplied appearance files before trusting a CLI exit code.

        Generated app configurations are captured in the successful receipt;
        they cannot be compared directly to the theme's source directory.
        """
        source, active = self.themes / slug, self.current / 'theme'
        if not (active / 'colors.toml').is_file():
            raise RuntimeError(f'Activation did not generate a palette for {slug}')
        community = self.entries[slug][3] == '.'
        paths = self.images(source / 'backgrounds')
        paths += [path for path in source.iterdir() if not path.name.startswith('.') and path.is_file()]
        for path in paths:
            if community and (path.is_symlink() or (path.parent == source and
                    (path.suffix == '.lua' or path.name in COMMUNITY_EXCLUSIONS))):
                continue
            target = active / path.relative_to(source)
            # Omarchy merges shell section overrides into shell.toml after
            # staging. Its generated result is covered by the active receipt.
            merged_shell = path.name == 'shell.toml' and any(active.glob('shell.*.toml'))
            if not target.is_file() or (not merged_shell and file_digest(path) != file_digest(target)):
                raise RuntimeError(f'Activation left an outdated or missing file: {target}')

    def invalidate_picker(self):
        # Omarchy's fast signature uses only directory mtimes. Replacing a file
        # inside backgrounds/ can leave that signature unchanged. Invalidate
        # derived selector metadata and only its indexed preview thumbnails.
        (self.cache / 'theme-selector/fast-signature').unlink(missing_ok=True)
        image_cache = self.cache / 'image-selector'
        for path in image_cache.glob('*.fast-signature'):
            path.unlink()
        index = image_cache / 'index.tsv'
        if index.is_file():
            prefix = str(self.cache / 'theme-selector/previews') + '/'
            for line in index.read_text().splitlines():
                fields = line.split('\t')
                if (len(fields) == 3 and fields[0].startswith(prefix)
                        and re.fullmatch(r'[0-9a-f]{32}', fields[2])):
                    (image_cache / f'{fields[2]}.jpg').unlink(missing_ok=True)

    def refresh_active(self, slug, desired):
        if self.selected() != slug:
            print('Theme selection changed during sync; activation deferred.')
            return
        background = self.background()
        self.active_receipt.unlink(missing_ok=True)
        self.run(['omarchy', 'theme', 'set', slug], extra_env={
            'OMARCHY_THEME_SKIP_BACKGROUND': '1', 'HYPRDOTS_THEME_AUTOPIN': '0'})
        if self.selected() != slug:
            print('Theme selection changed during activation; wallpaper refresh deferred.')
            return
        self.verify_applied(slug)
        preserved = background is not None and background.is_file()
        if not preserved:
            images = self.images(self.current / 'theme/backgrounds')
            if not images:
                raise RuntimeError(f'Activated theme has no wallpaper: {slug}')
            background = images[0]
        self.run(['omarchy', 'theme', 'bg', 'set', str(background)])
        actual_background = self.background()
        if (self.selected() != slug or self.active_stamp(slug) != desired
                or actual_background is None or not actual_background.is_file()
                or actual_background.resolve() != background.resolve()):
            raise RuntimeError('Theme or wallpaper changed during activation; run ./themes.sh sync again')
        write_receipt(self.active_receipt, slug=slug, source=desired,
                      contents=tree_digest(self.current / 'theme'))
        wallpaper_result = 'preserved selected wallpaper' if preserved else 'selected replacement wallpaper'
        print(f'Applied current managed theme: {slug}; {wallpaper_result}.')

    def sync(self, offline=False):
        # Serialize activation/receipts between root sync and themes.sh sync.
        self.state.mkdir(parents=True, exist_ok=True)
        with (self.state / 'sync.lock').open('a') as stream:
            fcntl.flock(stream, fcntl.LOCK_EX)
            slug = self.selected()
            desired = self.active_stamp(slug) if slug in self.entries else None
            status = self.active_status(slug, desired) if desired else 'unmanaged'
            previews = digest({name: self.source_stamp(name) for name in self.entries})
            preview_pending = not self.previews_current(previews)
            active_pending = desired is not None and status != 'current'
            if not active_pending and not preview_pending:
                print('Managed theme activation and previews are current.')
                return
            if offline or not self.desktop_ready():
                reason = 'offline mode' if offline else 'no usable desktop session'
                print(f'Theme refresh deferred ({reason}); run ./themes.sh sync in the desktop session.')
                return
            if active_pending:
                self.refresh_active(slug, desired)
            if preview_pending or active_pending:
                self.preview_receipt.unlink(missing_ok=True)
                self.invalidate_picker()
                self.run(['omarchy', 'theme', 'switcher', '--preload'])
                if not self.previews_match():
                    raise RuntimeError('Theme preview refresh did not produce the expected previews')
                write_receipt(self.preview_receipt, sources=previews)
                print('Refreshed managed theme previews.')

    def check(self):
        problems = []
        slug = self.selected()
        if slug in self.entries:
            status = self.active_status(slug, self.active_stamp(slug))
            if status != 'current':
                problems.append(f'Active theme {slug}: {status}')
        previews = digest({name: self.source_stamp(name) for name in self.entries})
        if not self.previews_current(previews):
            problems.append('Managed theme previews: stale or unverified')
        if problems:
            raise RuntimeError('; '.join(problems) + '. Run ./themes.sh sync in the desktop session.')
        print('Managed theme activation and previews are current.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('sync', 'check'))
    parser.add_argument('--user-home', type=Path, required=True)
    parser.add_argument('--lock', type=Path, required=True)
    args = parser.parse_args()
    try:
        activation = ThemeActivation(args.user_home, args.lock,
                                     Path(os.environ.get('OMARCHY_PATH') or '/usr/share/omarchy'),
                                     Path(os.environ.get('XDG_CACHE_HOME') or args.user_home / '.cache'))
        if args.action == 'check':
            activation.check()
        else:
            offline = any(os.environ.get(key) == '1' for key in
                          ('HYPRDOTS_OFFLINE', 'OMARCHY_THEME_OFFLINE', 'OMARCHY_THEME_HEADLESS'))
            activation.sync(offline=offline)
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f'Theme refresh: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
