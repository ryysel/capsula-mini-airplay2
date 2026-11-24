"""Execute the shipped hook installer in an isolated fake device filesystem."""
from pathlib import Path
import hashlib,subprocess,tempfile,unittest
ROOT=Path(__file__).resolve().parents[1]
PKG=ROOT/'packages/mini-stock'
def sha(data):return hashlib.sha256(data).hexdigest()

class HookTest(unittest.TestCase):
    def test_known_wrapper_install_idempotent_disable_and_unknown_refusal(self):
        with tempfile.TemporaryDirectory() as temp:
            d=Path(temp)
            package=d/'package';(package/'etc').mkdir(parents=True)
            (package/'etc/display-arbiter-launch.sh').write_bytes((PKG/'etc/display-arbiter-launch.sh').read_bytes())
            dest=d/'app';(dest/'etc').mkdir(parents=True);(dest/'bin').mkdir()
            (dest/'bin/libcapsula-display-arbiter.so').write_text('mock library')
            rom=d/'rom';rom.mkdir();upper=d/'upper';upper.mkdir()
            binary=b'mock firmware';(rom/'voice-agent').write_bytes(binary)
            stock=b'#!/bin/sh\nexec voice-agent "$@"\n'
            (rom/'voice-agent.sh').write_bytes(stock)
            wrapper=upper/'voice-agent.sh'
            old=b'#!/bin/sh\n# fixture fallback\nvoice-agent "$@" &\nwait "$!"\n'
            wrapper.write_bytes(old)
            block=(package/'etc/display-arbiter-launch.sh').read_bytes()
            expected=old.replace(b'voice-agent "$@" &\n',block)
            text=(PKG/'display-arbiter-install.sh').read_text()
            text=text.replace('/data/local/capsula-airplay',str(dest)).replace('/data/overlay/upper/usr/bin/voice-agent.sh',str(wrapper))
            text=text.replace('/rom/usr/bin/voice-agent.sh',str(rom/'voice-agent.sh')).replace('/rom/usr/bin/voice-agent',str(rom/'voice-agent'))
            for before,after in [
                ('e91c758edaae7ef258691438439906b4bd5986609a3be9fde946e59fc15ed9b7',sha(binary)),
                ('82a498025166d199343398ac7f9fdcb659c472f9b0de0ab784c30d9fc11713cb',sha(old)),
                ('99483ff16996719e7ed2201dcf1b4a63ab15b472f15068d1c6aa77272fa3041f',sha(expected)),
            ]:text=text.replace(before,after)
            script=package/'display-arbiter-install.sh';script.write_text(text)
            def run(mode,success=True):
                result=subprocess.run(['sh',str(script),mode],capture_output=True,text=True)
                self.assertEqual(result.returncode==0,success,result.stdout+result.stderr)
            run('check');self.assertEqual(wrapper.read_bytes(),old)
            run('install');self.assertEqual(wrapper.read_bytes(),expected)
            flag=dest/'etc/mini-display-arbiter.enabled'
            self.assertTrue(flag.exists())
            run('install');self.assertEqual(wrapper.read_bytes(),expected)
            run('disable');self.assertFalse(flag.exists())
            wrapper.write_text('unknown wrapper\n')
            run('check',False);self.assertEqual(wrapper.read_text(),'unknown wrapper\n')
            wrapper.write_bytes(old)
            pending=dest/'etc/mini-display-arbiter.pending';pending.touch()
            run('install',False);self.assertEqual(wrapper.read_bytes(),old)
            pending.unlink()
            wrapper.unlink();wrapper.symlink_to(rom/'voice-agent.sh')
            run('check',False);self.assertEqual((rom/'voice-agent.sh').read_bytes(),stock)

if __name__=='__main__':unittest.main()
