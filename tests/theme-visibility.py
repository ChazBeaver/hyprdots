#!/usr/bin/env python3
"""Verify menu exclusions and refreshes without accessing the desktop."""
import importlib.util
from pathlib import Path
import hashlib
import sys
import tempfile
import unittest

helper = Path(sys.argv.pop(1)) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / 'bin/linux/hyprdots-theme-switcher.py'
spec = importlib.util.spec_from_file_location('theme_switcher', helper)
switcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(switcher)


class ThemeVisibilityTest(unittest.TestCase):
    def test_hidden_stock_retains_personal_and_refreshes_previews(self):
        with tempfile.TemporaryDirectory() as tmp:
            cache = Path(tmp)
            source = cache / 'omarchy/theme-selector/previews'
            source.mkdir(parents=True)
            assets = cache / 'assets'
            assets.mkdir()
            for name in ('ethereal', 'ethereal-personal', 'blue-sky', 'blue-green'):
                asset = assets / f'{name}.png'
                asset.write_bytes(name.encode())
                (source / asset.name).symlink_to(asset)
            hidden = cache / 'hidden.txt'
            hidden.write_text('# Personal replacements\nethereal\n')
            previews = switcher.prepare_previews(cache, hidden)
            self.assertEqual({p.stem for p in previews.iterdir()}, {'ethereal-personal', 'blue-sky', 'blue-green'})
            key = hashlib.md5(str(previews).encode()).hexdigest()
            row_dir = cache / 'omarchy/image-selector'
            row_dir.mkdir()
            for suffix in ('rows', 'signature', 'fast-signature'):
                (row_dir / f'{key}.{suffix}').write_text('stale')
            (row_dir / 'unrelated.rows').write_text('keep')
            replacement = assets / 'new-blue-sky.jpg'
            replacement.write_bytes(b'One Dark')
            (source / 'blue-sky.png').unlink()
            (source / 'blue-sky.jpg').symlink_to(replacement)
            (source / 'blue-green.png').unlink()
            switcher.prepare_previews(cache, hidden)
            self.assertEqual({p.name for p in previews.iterdir()}, {'ethereal-personal.png', 'blue-sky.jpg'})
            self.assertEqual((previews / 'blue-sky.jpg').read_bytes(), b'One Dark')
            self.assertEqual(list(row_dir.iterdir()), [row_dir / 'unrelated.rows'])
            hidden.write_text('')
            switcher.prepare_previews(cache, hidden)
            self.assertTrue((previews / 'ethereal.png').exists())
            self.assertTrue((source / 'ethereal.png').exists())

    def test_invalid_slug_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            hidden = Path(tmp) / 'hidden.txt'
            hidden.write_text('../ethereal\n')
            with self.assertRaises(ValueError):
                switcher.prepare_previews(Path(tmp), hidden)


if __name__ == '__main__':
    unittest.main()
