"""Exercise actual installer and boot fragments without device access."""
from pathlib import Path
import subprocess,tempfile,unittest
ROOT=Path(__file__).resolve().parents[1]
PKG=ROOT/'packages/mini-stock'

class DisplayModeTest(unittest.TestCase):
    def test_modes_preserve_enable_disable(self):
        source=(PKG/'install.sh').read_text()
        fragment=source.split('# BEGIN DISPLAY MODE MIGRATION (also executed by regression tests)\n')[1].split('# END DISPLAY MODE MIGRATION')[0]
        with tempfile.TemporaryDirectory() as temp:
            d=Path(temp);(d/'etc').mkdir()
            marker=d/'runtime'
            fragment=fragment.replace('/tmp/capsula-mini-display-vu',str(marker))
            flag=d/'etc/mini-display-vu.enabled'
            def run(mode):
                subprocess.run(['sh','-c','set -eu\nDEST=$1\ndisplay_mode=$2\n'+fragment,'sh',str(d),mode],check=True)
            run('preserve');self.assertFalse(flag.exists())
            run('vu');self.assertTrue(flag.exists())
            run('preserve');self.assertTrue(flag.exists())
            marker.touch()
            run('clock');self.assertFalse(flag.exists());self.assertFalse(marker.exists())
            run('preserve');self.assertFalse(flag.exists())

    def test_real_start_one_boot_marker(self):
        hook=(PKG/'etc/S99airplay').read_text().split('case "$1" in\n')[0]
        with tempfile.TemporaryDirectory() as temp:
            d=Path(temp)
            for directory in ['etc','run','tmp']: (d/directory).mkdir()
            hook=hook.replace('/var/run/',str(d/'run')+'/').replace('/tmp/capsula-ui.log',str(d/'tmp/log')).replace('/tmp/capsula-mini-display-vu',str(d/'tmp/marker'))
            script=hook+'\nD=$1\nrunning() { return 1; }\nnohup() { :; }\nstart_one capsula-ui\nwait\n'
            def start():
                subprocess.run(['sh','-c',script,'sh',str(d)],check=True)
            start();self.assertFalse((d/'tmp/marker').exists())
            (d/'etc/mini-display-vu.enabled').touch()
            start();self.assertTrue((d/'tmp/marker').exists())
            (d/'etc/mini-display-vu.enabled').unlink()
            start();self.assertFalse((d/'tmp/marker').exists())

if __name__=='__main__': unittest.main()
