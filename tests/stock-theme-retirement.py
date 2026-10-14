#!/usr/bin/env python3
"""Exercise stock-theme retirement in a disposable filesystem."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

helper = Path(sys.argv.pop(1)) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / 'scripts/retire-stock-themes.py'
spec = importlib.util.spec_from_file_location('retirement', helper)
retirement = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = retirement
spec.loader.exec_module(retirement)


class StockThemeRetirementTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.repo = self.root / 'repo'
        self.user_home = self.root / 'home'
        (self.repo / 'config').mkdir(parents=True)
        (self.repo / 'config/retired-stock-themes.txt').write_text('ethereal\n')
        (self.repo / 'config/themes.lock.tsv').write_text('ethereal\tpersonal-drafts\tgit@github.com:example/vault.git\t' + 'a'*40 + '\tthemes/ethereal\n')
        personal = self.user_home / '.local/share/hyprdots/theme-sources/personal-drafts/themes/ethereal'
        personal.mkdir(parents=True)
        (personal / 'colors.toml').write_text('personal palette')
        installed = self.user_home / '.config/omarchy/themes/ethereal'
        installed.parent.mkdir(parents=True)
        installed.symlink_to(personal)
        self.stock = self.root / 'usr/share/omarchy/themes/ethereal'
        self.stock.mkdir(parents=True)
        (self.stock / 'colors.toml').write_text('stock palette')
        self.unrelated = self.root / 'usr/share/omarchy/themes/nord'
        self.unrelated.mkdir()
        self.pacman = self.root / 'etc/pacman.conf'
        self.pacman.parent.mkdir()
        self.original = '[options]\nArchitecture = auto\nNoExtract = usr/share/doc/unrelated/*\n\n[core]\nServer = https://example.invalid/$repo/os/$arch\n'
        self.pacman.write_text(self.original)

    def test_removal_preserves_other_themes_and_pacman_settings(self):
        protected = self.root / 'protected'
        protected.write_text('keep')
        (self.stock / 'external-link').symlink_to(protected)
        plan = retirement.plan_retirement(self.repo, self.user_home, self.root)
        retirement.apply_retirement(plan)
        self.assertFalse(self.stock.exists())
        self.assertTrue(self.unrelated.is_dir())
        self.assertEqual(protected.read_text(), 'keep')
        self.assertEqual((self.user_home / '.config/omarchy/themes/ethereal/colors.toml').read_text(), 'personal palette')
        self.assertIn('NoExtract = usr/share/doc/unrelated/*', self.pacman.read_text())
        self.assertEqual(next(self.pacman.parent.glob('pacman.conf.hyprdots-backup.*')).read_text(), self.original)
        effective = subprocess.check_output(['pacman-conf', '--config', str(self.pacman), 'NoExtract'], text=True).splitlines()
        self.assertIn('usr/share/doc/unrelated/*', effective)
        self.assertTrue(set(plan.patterns) <= set(effective))
        again = retirement.plan_retirement(self.repo, self.user_home, self.root)
        self.assertEqual(retirement.drift(again), [])
        retirement.apply_retirement(again)
        self.assertEqual(len(list(self.pacman.parent.glob('pacman.conf.hyprdots-backup.*'))), 1)
        self.stock.mkdir()
        self.assertTrue(retirement.drift(again))

    def test_requires_installed_personal_replacement(self):
        (self.user_home / '.config/omarchy/themes/ethereal').unlink()
        with self.assertRaisesRegex(ValueError, 'Install the pinned personal replacement'):
            retirement.plan_retirement(self.repo, self.user_home, self.root)
        self.assertEqual(self.pacman.read_text(), self.original)
        self.assertTrue(self.stock.is_dir())

    def test_rejects_paths_and_stock_symlinks(self):
        manifest = self.repo / 'config/retired-stock-themes.txt'
        manifest.write_text('../ethereal\n')
        with self.assertRaises(ValueError):
            retirement.plan_retirement(self.repo, self.user_home, self.root)
        manifest.write_text('ethereal\n')
        (self.stock / 'colors.toml').unlink()
        self.stock.rmdir()
        self.stock.symlink_to(self.unrelated)
        with self.assertRaisesRegex(ValueError, 'unexpected stock theme path'):
            retirement.plan_retirement(self.repo, self.user_home, self.root)


if __name__ == '__main__':
    unittest.main()
