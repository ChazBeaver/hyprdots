#!/usr/bin/env python3
"""Remove explicitly retired stock themes and prevent package reinstalls."""

import argparse
from dataclasses import dataclass
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time


@dataclass
class Plan:
    targets: list
    pacman: Path
    pacman_text: str
    exclusion: Path
    exclusion_text: str
    patterns: list


def plan_retirement(repo, user_home, system_root=Path('/')):
    slugs = []
    for line in (repo / 'config/retired-stock-themes.txt').read_text().splitlines():
        slug = line.strip()
        if not slug or slug.startswith('#'):
            continue
        if not re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*', slug) or slug in slugs:
            raise ValueError(f'Invalid or duplicate retired stock theme: {slug}')
        slugs.append(slug)
    entries = {}
    for line in (repo / 'config/themes.lock.tsv').read_text().splitlines():
        if line and not line.startswith('#'):
            fields = line.split('\t')
            entries[fields[0]] = fields

    targets, patterns = [], []
    for slug in slugs:
        entry = entries.get(slug, [])
        if len(entry) != 5 or entry[1] != 'personal-drafts' or entry[4] != f'themes/{slug}':
            raise ValueError(f'{slug} must have a personal vault pin before retiring the stock theme')
        replacement = user_home / f'.config/omarchy/themes/{slug}'
        expected = user_home / f'.local/share/hyprdots/theme-sources/personal-drafts/themes/{slug}'
        if (not replacement.is_symlink() or replacement.resolve() != expected.resolve()
                or not (replacement / 'colors.toml').is_file()):
            raise ValueError(f'Install the pinned personal replacement before retiring {slug}')
        target = system_root / f'usr/share/omarchy/themes/{slug}'
        if target.is_symlink() or target.resolve() != target or (target.exists() and not target.is_dir()):
            raise ValueError(f'Refusing unexpected stock theme path: {target}')
        targets.append(target)
        patterns.extend([f'usr/share/omarchy/themes/{slug}/', f'usr/share/omarchy/themes/{slug}/*'])

    exclusion = system_root / 'etc/pacman.d/hyprdots-retired-themes.conf'
    pacman = system_root / 'etc/pacman.conf'
    if exclusion.is_symlink() or pacman.is_symlink():
        raise ValueError('Refusing symlinked pacman configuration')
    lines = pacman.read_text().splitlines(keepends=True)
    include = f'Include = {exclusion}'
    section = ''
    options_end = None
    includes = 0
    for index, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith('[') and stripped.endswith(']'):
            if section == '[options]' and options_end is None:
                options_end = index
            section = stripped
        if stripped == include:
            if section != '[options]':
                raise ValueError('Managed pacman include must be in [options]')
            includes += 1
    if [line.strip() for line in lines].count('[options]') != 1 or includes > 1:
        raise ValueError('Expected one [options] section and at most one managed include')
    if not includes:
        index = options_end if options_end is not None else len(lines)
        lines.insert(index, f'{include}\n\n')
    text = '# Managed by hyprdots: ./themes.sh retire-stock\n'
    if patterns:
        text += 'NoExtract = ' + ' '.join(patterns) + '\n'
    return Plan(targets, pacman, ''.join(lines), exclusion, text, patterns)


def drift(plan):
    errors = []
    for path, expected in [(plan.pacman, plan.pacman_text), (plan.exclusion, plan.exclusion_text)]:
        if not path.exists() or path.read_text() != expected:
            errors.append(f'Stock-theme package exclusion is not configured: {path}')
    errors.extend(f'Retired stock theme remains installed: {path.name}' for path in plan.targets if path.exists())
    return errors


def atomic_write(path, text):
    if path.exists() and path.read_text() == text:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = path.stat().st_mode & 0o777 if path.exists() else 0o644
    if path.exists():
        shutil.copy2(path, path.with_name(f'{path.name}.hyprdots-backup.{time.time_ns()}'))
    with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        stream.write(text)
    try:
        temporary.chmod(mode)
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def apply_retirement(plan):
    # Preserve all unrelated pacman options; install the exclusion before deletion.
    atomic_write(plan.exclusion, plan.exclusion_text)
    atomic_write(plan.pacman, plan.pacman_text)
    for target in plan.targets:
        if target.exists():
            shutil.rmtree(target)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--user-home', required=True, type=Path)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    try:
        plan = plan_retirement(repo, args.user_home)
        errors = drift(plan)
        if errors and args.check:
            for error in errors:
                print(error, file=sys.stderr)
            print('Run ./themes.sh retire-stock to apply the recorded removals.', file=sys.stderr)
            return 1
        if errors:
            if os.geteuid() != 0:
                elevator = 'sudo' if sys.stdin.isatty() else 'pkexec'
                os.execvp(elevator, [elevator, '/usr/bin/python3', '-B', str(Path(__file__).resolve()),
                                    '--user-home', str(args.user_home)])
            apply_retirement(plan)
        effective = subprocess.check_output(['pacman-conf', 'NoExtract'], text=True).splitlines()
        if not set(plan.patterns) <= set(effective):
            raise ValueError('pacman did not load all recorded stock-theme exclusions')
        print('Retired stock themes are absent and excluded from package extraction.')
        return 0
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f'Stock-theme retirement failed: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
