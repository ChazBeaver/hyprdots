#!/usr/bin/env python3
"""Exercise theme refresh against local Git sources and a simulated desktop."""

import contextlib
import importlib.util
import io
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('theme_activation', REPO / 'scripts/theme-activation.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ActivationTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.user_home = self.root / 'user'
        self.source = self.user_home / '.local/share/hyprdots/theme-sources/personal-drafts'
        self.source.mkdir(parents=True)
        self.git('init', '-q', '-b', 'main')
        self.themes = self.user_home / '.config/omarchy/themes'
        self.themes.mkdir(parents=True)
        for name in ('one', 'two'):
            theme = self.source / 'themes' / name
            (theme / 'backgrounds').mkdir(parents=True)
            (theme / 'colors.toml').write_text(f'background = "#{name}"\n')
            for image in ('a.png', 'b.webp'):
                (theme / 'backgrounds' / image).write_text(f'{name}/{image}')
            (theme / 'preview.webp').symlink_to('backgrounds/b.webp')
            (self.themes / name).symlink_to(theme)
        self.lock = self.root / 'themes.lock.tsv'
        self.commit()
        self.system = self.root / 'omarchy'
        (self.system / 'default/themed').mkdir(parents=True)
        (self.system / 'default/themed/ghostty.conf.tpl').write_text('background = {{ background }}')
        self.cache_home = self.root / 'cache'
        self.current = self.user_home / '.local/state/omarchy/current'
        self.current.mkdir(parents=True)
        (self.current / 'theme.name').write_text('one\n')
        (self.current / 'theme').mkdir()
        (self.current / 'theme/colors.toml').write_text('stale palette')
        self.calls = []
        self.session = True
        self.failure = None
        self.noop = False
        self.after_theme_set = None
        self.refresh = self.instance()

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.source), *args], text=True).strip()

    def commit(self):
        self.git('add', '.')
        self.git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                 'commit', '-qm', 'fixture')
        revision = self.git('rev-parse', 'HEAD')
        self.lock.write_text(''.join(f'{name}\tpersonal-drafts\tgit@github.com:example/vault.git'
                                     f'\t{revision}\tthemes/{name}\n' for name in ('one', 'two')))

    def instance(self):
        return module.ThemeActivation(self.user_home, self.lock, self.system,
                                      self.cache_home, run=self.run_command)

    def edit(self, name='one'):
        (self.source / 'themes' / name / 'colors.toml').write_text('background = "#changed"\n')
        self.commit()
        self.refresh = self.instance()

    def run_command(self, args, *, extra_env=None, timeout=120):
        if args[0] == 'git':
            return module.command(args, extra_env=extra_env, timeout=timeout)
        self.calls.append(tuple(args))
        if args[0] in ('omarchy-shell', 'hyprctl'):
            if not self.session:
                raise RuntimeError('no desktop socket')
            return '[{"id": 0}]' if args[0] == 'hyprctl' else 'pong'
        if self.failure == tuple(args[2:4]):
            raise RuntimeError('injected command failure')
        if args[2] == 'set':
            self.assertEqual(extra_env, {'OMARCHY_THEME_SKIP_BACKGROUND': '1',
                                        'HYPRDOTS_THEME_AUTOPIN': '0'})
            if not self.noop:
                shutil.rmtree(self.current / 'theme')
                shutil.copytree(self.themes / args[3], self.current / 'theme', symlinks=True)
                (self.current / 'theme/ghostty.conf').write_text('generated configuration')
                (self.current / 'theme.name').write_text(args[3] + '\n')
            if self.after_theme_set:
                self.after_theme_set()
        elif args[2:4] == ['bg', 'set']:
            path = self.current / 'background'
            path.unlink(missing_ok=True)
            path.symlink_to(Path(args[4]).resolve())
        elif args[2:4] == ['switcher', '--preload']:
            # Model the packaged selector's cache shortcut: nested edits would
            # be missed without invalidating its fast signature first.
            selector = self.cache_home / 'omarchy/theme-selector'
            if (selector / 'fast-signature').exists():
                return ''
            previews = selector / 'previews'
            previews.mkdir(parents=True, exist_ok=True)
            for slug in self.refresh.entries:
                target = self.refresh.expected_preview(slug)
                link = previews / f'{slug}{target.suffix.lower()}'
                link.unlink(missing_ok=True)
                link.symlink_to(target)
            (selector / 'fast-signature').write_text('cached')
        else:
            self.fail(f'unexpected command: {args}')
        return ''

    def sync(self, **kwargs):
        with contextlib.redirect_stdout(io.StringIO()) as output:
            self.refresh.sync(**kwargs)
        return output.getvalue()

    def selected_wallpaper(self, path):
        link = self.current / 'background'
        link.unlink(missing_ok=True)
        link.symlink_to(path)

    def desktop_actions(self):
        return [args for args in self.calls if args[0] == 'omarchy']

    def test_first_sync_repairs_existing_stale_copy_and_second_sync_is_quiet(self):
        original_lock = self.lock.read_bytes()
        self.sync()
        self.assertEqual((self.current / 'theme/colors.toml').read_bytes(),
                         (self.themes / 'one/colors.toml').read_bytes())
        self.assertEqual((self.current / 'theme.name').read_text().strip(), 'one')
        self.assertEqual(self.refresh.background(), self.current / 'theme/backgrounds/a.png')
        self.assertEqual(self.lock.read_bytes(), original_lock)
        receipt = self.refresh.active_receipt.stat().st_mtime_ns
        self.calls.clear()
        self.sync()
        self.assertEqual(self.desktop_actions(), [])
        self.assertEqual(self.refresh.active_receipt.stat().st_mtime_ns, receipt)

    def test_already_updated_checkout_still_refreshes_active_copy(self):
        self.sync()
        self.edit()
        with self.assertRaisesRegex(RuntimeError, 'stale source'):
            self.refresh.check()
        self.calls.clear()
        self.sync()
        self.assertIn(('omarchy', 'theme', 'set', 'one'), self.calls)
        with contextlib.redirect_stdout(io.StringIO()):
            self.refresh.check()

    def test_sibling_update_only_refreshes_previews(self):
        self.sync()
        self.edit('two')
        self.calls.clear()
        self.sync()
        self.assertEqual(self.desktop_actions(), [('omarchy', 'theme', 'switcher', '--preload')])

    def test_retains_selected_wallpaper_and_updated_bytes(self):
        self.sync()
        selected = self.current / 'theme/backgrounds/b.webp'
        self.selected_wallpaper(selected)
        (self.themes / 'one/backgrounds/b.webp').write_text('updated wallpaper')
        self.commit()
        self.refresh = self.instance()
        self.sync()
        self.assertEqual(self.refresh.background(), selected)
        self.assertEqual(selected.read_text(), 'updated wallpaper')

    def test_retains_valid_external_wallpaper(self):
        self.sync()
        selected = self.root / 'personal image.png'
        selected.write_text('external wallpaper')
        self.selected_wallpaper(selected)
        self.edit()
        self.sync()
        self.assertEqual(self.refresh.background(), selected)

    def test_removed_wallpaper_falls_back_to_updated_theme(self):
        self.sync()
        self.selected_wallpaper(self.current / 'theme/backgrounds/b.webp')
        (self.themes / 'one/backgrounds/b.webp').rename(self.themes / 'one/backgrounds/c.webp')
        (self.themes / 'one/preview.webp').unlink()
        (self.themes / 'one/preview.webp').symlink_to('backgrounds/c.webp')
        self.commit()
        self.refresh = self.instance()
        self.sync()
        self.assertEqual(self.refresh.background(), self.current / 'theme/backgrounds/a.png')
        preview = self.cache_home / 'omarchy/theme-selector/previews/one.webp'
        self.assertEqual(preview.resolve(), (self.themes / 'one/backgrounds/c.webp').resolve())

    def test_stock_unmanaged_and_missing_selection_are_preserved(self):
        for selected in ('stock-theme', 'my-unmanaged-theme', ''):
            with self.subTest(selected=selected):
                (self.current / 'theme.name').write_text(selected)
                self.calls.clear()
                self.sync()
                self.assertEqual(self.refresh.selected(), selected)
                self.assertFalse(any(args[2] == 'set' for args in self.desktop_actions()))

    def test_empty_lock_has_no_desktop_work(self):
        self.lock.write_text('# No managed themes\n')
        self.refresh = self.instance()
        self.sync()
        with contextlib.redirect_stdout(io.StringIO()):
            self.refresh.check()
        self.assertEqual(self.calls, [])

    def test_offline_and_missing_session_defer_then_retry(self):
        self.assertIn('deferred', self.sync(offline=True))
        self.assertEqual(self.calls, [])
        self.assertFalse(self.refresh.active_receipt.exists())
        with self.assertRaisesRegex(RuntimeError, 'unverified'):
            self.refresh.check()
        self.session = False
        self.assertIn('deferred', self.sync())
        self.assertEqual(self.desktop_actions(), [])
        self.session = True
        self.sync()
        self.assertTrue(self.refresh.active_receipt.exists())

    def test_activation_error_and_false_success_are_retryable(self):
        self.failure = ('set', 'one')
        with self.assertRaisesRegex(RuntimeError, 'injected'):
            self.sync()
        self.assertFalse(self.refresh.active_receipt.exists())
        self.failure = None
        self.noop = True
        with self.assertRaisesRegex(RuntimeError, 'outdated or missing file'):
            self.sync()
        self.assertFalse(self.refresh.active_receipt.exists())
        self.noop = False
        self.sync()
        self.assertTrue(self.refresh.active_receipt.exists())

    def test_false_success_cannot_certify_a_stale_appearance_override(self):
        self.sync()
        (self.themes / 'one/btop.theme').write_text('updated btop appearance')
        self.commit()
        self.refresh = self.instance()
        self.noop = True
        with self.assertRaisesRegex(RuntimeError, 'btop.theme'):
            self.sync()
        self.assertFalse(self.refresh.active_receipt.exists())

    def test_background_failure_invalidates_old_receipt_before_retry(self):
        self.sync()
        (self.current / 'theme/ghostty.conf').write_text('local drift')
        self.failure = ('bg', 'set')
        with self.assertRaisesRegex(RuntimeError, 'injected'):
            self.sync()
        self.assertFalse(self.refresh.active_receipt.exists())
        self.failure = None
        self.calls.clear()
        self.sync()
        self.assertIn(('omarchy', 'theme', 'set', 'one'), self.calls)

    def test_preview_failure_retries_without_reapplying_successful_theme(self):
        self.failure = ('switcher', '--preload')
        with self.assertRaisesRegex(RuntimeError, 'injected'):
            self.sync()
        self.assertTrue(self.refresh.active_receipt.exists())
        self.assertFalse(self.refresh.preview_receipt.exists())
        self.failure = None
        self.calls.clear()
        self.sync()
        self.assertEqual(self.desktop_actions(), [('omarchy', 'theme', 'switcher', '--preload')])

    def test_missing_preview_cache_is_rebuilt(self):
        self.sync()
        (self.cache_home / 'omarchy/theme-selector/previews/two.webp').unlink()
        with self.assertRaisesRegex(RuntimeError, 'previews'):
            self.refresh.check()
        self.calls.clear()
        self.sync()
        self.assertEqual(self.desktop_actions(), [('omarchy', 'theme', 'switcher', '--preload')])

    def test_nested_wallpaper_edit_invalidates_only_preview_thumbnails(self):
        self.sync()
        image_cache = self.cache_home / 'omarchy/image-selector'
        image_cache.mkdir()
        preview = self.cache_home / 'omarchy/theme-selector/previews/two.webp'
        old_hash, other_hash = 'a' * 32, 'b' * 32
        (image_cache / 'index.tsv').write_text(f'{preview}\t1:1\t{old_hash}\n'
                                              f'/unrelated/image.png\t1:1\t{other_hash}\n')
        old_thumbnail = image_cache / f'{old_hash}.jpg'
        old_thumbnail.write_text('old preview')
        other_thumbnail = image_cache / f'{other_hash}.jpg'
        other_thumbnail.write_text('unrelated thumbnail')
        fast_signature = image_cache / 'test.fast-signature'
        fast_signature.write_text('cached rows')
        wallpaper = self.themes / 'two/backgrounds/b.webp'
        original = wallpaper.stat()
        wallpaper.write_bytes(b'X' * original.st_size)
        os.utime(wallpaper, ns=(original.st_atime_ns, original.st_mtime_ns))
        self.commit()
        self.refresh = self.instance()
        self.calls.clear()
        self.sync()
        self.assertFalse(old_thumbnail.exists())
        self.assertTrue(other_thumbnail.exists())
        self.assertFalse(fast_signature.exists())
        self.assertEqual(self.desktop_actions(), [('omarchy', 'theme', 'switcher', '--preload')])

    def test_selection_changed_before_or_during_refresh_is_respected(self):
        stamp = self.refresh.active_stamp('one')
        (self.current / 'theme.name').write_text('two')
        with contextlib.redirect_stdout(io.StringIO()):
            self.refresh.refresh_active('one', stamp)
        self.assertEqual(self.desktop_actions(), [])
        (self.current / 'theme.name').write_text('one')
        self.after_theme_set = lambda: (self.current / 'theme.name').write_text('two')
        self.sync()
        self.assertEqual(self.refresh.selected(), 'two')
        self.assertFalse(self.refresh.active_receipt.exists())
        self.assertFalse(any(args[2] == 'bg' for args in self.desktop_actions()))

    def test_doctor_is_read_only_and_detects_modified_generated_files(self):
        self.sync()
        self.calls.clear()
        before = {path: (path.stat().st_mtime_ns, path.read_bytes())
                  for path in self.refresh.state.iterdir() if path.is_file()}
        with contextlib.redirect_stdout(io.StringIO()):
            self.refresh.check()
        after = {path: (path.stat().st_mtime_ns, path.read_bytes())
                 for path in self.refresh.state.iterdir() if path.is_file()}
        self.assertEqual(before, after)
        self.assertEqual(self.calls, [])
        (self.current / 'theme/ghostty.conf').write_text('stale generated file')
        with self.assertRaisesRegex(RuntimeError, 'stale active files'):
            self.refresh.check()

    def test_corrupt_receipt_and_changed_templates_require_refresh(self):
        self.sync()
        self.refresh.active_receipt.write_text('{broken')
        with self.assertRaisesRegex(RuntimeError, 'unverified'):
            self.refresh.check()
        self.sync()
        (self.system / 'default/themed/ghostty.conf.tpl').write_text('new template')
        self.calls.clear()
        self.sync()
        self.assertIn(('omarchy', 'theme', 'set', 'one'), self.calls)


if __name__ == '__main__':
    unittest.main()
