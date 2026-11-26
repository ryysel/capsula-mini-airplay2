"""Exercise the candidate installer fragments in isolated directories."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BIG = ROOT / "packages/capsula-2019"
MINI = ROOT / "packages/mini-stock"

class UpgradeTest(unittest.TestCase):
    def test_name_edit_and_timing_preservation(self):
        text = (BIG / "install.sh").read_text()
        fragment = text[text.index('conf=$DEST'):text.index('# Snapshot managed')]
        with tempfile.TemporaryDirectory() as d:
            dest = Path(d)
            (dest / "etc").mkdir()
            conf = dest / "etc/shairport-sync.conf"
            template = (BIG / "etc/shairport-sync.conf").read_text()
            conf.write_text(template)
            subprocess.run(["sh", str(BIG/"etc/apply-timing-profile.sh"), str(conf), "synchronized"], check=True)
            previous = conf.read_text().split("metadata =",1)[1]
            result = subprocess.run(["sh", "-ec", 'DEST=$1; name="New Room"; timing_mode=;\n'+fragment+'\ncat "$prepared"', "sh", d], cwd=BIG, text=True, capture_output=True, check=True)
            self.assertIn('name = "New Room";', result.stdout)
            self.assertIn('offset=0.0',result.stdout)
            self.assertEqual(result.stdout.split('metadata =',1)[1],previous)

    def test_rollback_restores_preexisting_files(self):
        installer = (BIG / "install.sh").read_text()
        start = installer.index("finish_install()")
        end = installer.index("was_running=no", start)
        with tempfile.TemporaryDirectory() as d:
            base = Path(d)
            backup = base / "snapshot"
            one = base / "managed"
            two = base / "new"
            prior = Path(str(backup) + str(one))
            prior.parent.mkdir(parents=True)
            prior.write_text("previous")
            one.write_text("broken")
            two.write_text("created")
            (backup / "paths").write_text(f"{one}\n{two}\n")
            script = ('BASE=$1; BACKUP=$2; was_running=no; prepared=$BASE/prepared\n'
                      + installer[start:end] + '\ntrap finish_install EXIT; exit 17')
            result = subprocess.run(["sh", "-ec", script, "sh", d, str(backup)])
            self.assertEqual(result.returncode, 17)
            self.assertEqual(one.read_text(), "previous")
            self.assertFalse(two.exists())

    def test_mini_backup_excludes_trial_binaries(self):
        script = (MINI/"install.sh").read_text()
        start = script.index("backup=none\nif [ -d")
        end = script.index("# Stop only", start)
        import tarfile
        with tempfile.TemporaryDirectory() as d:
            dest = Path(d) / "installed"
            (dest / "bin").mkdir(parents=True)
            (dest / "bin/old").write_text("previous")
            (dest / "panel.json").write_text("calibration")
            (dest / "trial").mkdir()
            parts = next(line for line in script.splitlines() if line.startswith("backup_parts="))
            subprocess.run(["sh","-ec",'DEST=$1; check=no; required=0; free=1000000; die(){ exit 1; }\n'+parts+'\n'+script[start:end],"sh",str(dest)],check=True)
            with tarfile.open(next(Path(d).glob("*.tar.gz"))) as archive:
                self.assertEqual(archive.extractfile("bin/old").read(), b"previous")
                self.assertEqual(archive.extractfile("panel.json").read(), b"calibration")
                self.assertNotIn("trial", archive.getnames())

if __name__ == "__main__":
    unittest.main()
