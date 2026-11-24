"""Run the stock-Mini installer's real timing rewrite without touching hardware."""
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "packages" / "mini-stock"


def migrate(config: str, mode: str) -> str:
    installer = (PACKAGE / "install.sh").read_text()
    start = installer.index('case "$timing_mode" in\n    synchronized) buffer=')
    finish_marker = 'mv "$CONF.new" "$CONF"'
    end = installer.index(finish_marker, start) + len(finish_marker)
    fragment = installer[start:end]
    with tempfile.TemporaryDirectory() as temp:
        path = Path(temp) / "receiver.conf"
        path.write_text(config)
        script = 'set -eu\nCONF=$1\ntiming_mode=$2\n' + fragment
        subprocess.run(["sh", "-c", script, "sh", str(path), mode], check=True)
        return path.read_text()


def number(config: str, key: str) -> float:
    matches = re.findall(r"^\s*" + re.escape(key) + r"\s*=\s*([-0-9.]+);", config, re.M)
    if len(matches) != 1:
        raise AssertionError(f"{key}: expected one assignment, found {matches!r}")
    return float(matches[0])


class StockMiniTimingTest(unittest.TestCase):
    def setUp(self):
        self.template = (PACKAGE / "etc/shairport-sync.conf").read_text()

    def assert_fast(self, config):
        self.assertEqual(number(config, "audio_backend_buffer_desired_length_in_seconds"), .15)
        self.assertEqual(number(config, "audio_backend_latency_offset_in_seconds"), -1.7)

    def test_fresh_install_agrees_with_shipped_template(self):
        self.assert_fast(self.template)
        self.assert_fast(migrate(self.template, "fast_audio"))

    def test_upgrade_does_not_reintroduce_100ms_budget(self):
        previous = self.template.replace(
            "audio_backend_buffer_desired_length_in_seconds = 0.15;",
            "audio_backend_buffer_desired_length_in_seconds = 0.10;",
        ).replace('name = "VK Capsula Mini AirPlay";', 'name = "Test Room";')
        candidate = migrate(previous, "fast_audio")
        self.assert_fast(candidate)
        self.assertIn('name = "Test Room";', candidate)
        self.assertIn('volume_control_profile = "flat";', candidate)
        self.assertIn('output_device = "master";', candidate)
        self.assertIn('include_cover_art = "yes";', candidate)
        self.assertEqual(candidate, migrate(candidate, "fast_audio"))

    def test_synchronized_then_fast_again(self):
        synchronized = migrate(self.template, "synchronized")
        self.assertEqual(number(synchronized, "audio_backend_buffer_desired_length_in_seconds"), .20)
        self.assertEqual(number(synchronized, "audio_backend_latency_offset_in_seconds"), 0)
        self.assert_fast(migrate(synchronized, "fast_audio"))


if __name__ == "__main__":
    unittest.main()
