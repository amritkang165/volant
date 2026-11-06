#!/usr/bin/env python3
"""Exercise website shipping boundaries with isolated commands; never deploy or use credentials."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
FAKE = r'''#!/usr/bin/env python3
import json, os, pathlib, shutil, sys
name=pathlib.Path(sys.argv[0]).name
args=sys.argv[1:]
root=pathlib.Path(os.environ['SHIP_FIXTURE'])
mode=os.environ.get('SHIP_CASE','success')
with (root/'calls').open('a') as f: f.write(json.dumps([name,*args])+'\n')
if name=='git':
    if args[0]=='-C': args=args[2:]
    if args[0]=='rev-parse': print('abc123')
    elif args[0]=='status' and mode=='dirty': print(' M website/app/page.tsx')
    elif args[:2]==['worktree','add']: shutil.copytree(root/'source',args[-2])
    elif args[:2]==['worktree','remove']: shutil.rmtree(args[-1])
elif name=='gh':
    if args[0]=='api': print('7')
    elif args[:2]==['pr','checks']:
        print(json.dumps([{'name':'PR gate','state':'SUCCESS'},{'name':'security / website','state':'PENDING' if mode=='pending' else 'SUCCESS'}]))
        if mode=='pending': sys.exit(8)
elif name=='npx':
    if 'whoami' in args: print('You are logged in')
    elif 'deploy' in args: print('Current Version ID: 12345678-abcd-1234-abcd-123456789abc')
elif name=='curl':
    if '-w' in args: print('301 https://usevolant.com/'); sys.exit()
    url=next(a for a in args if a.startswith('https://'))
    file=url.split('/')[-1].split('?')[0]
    out=pathlib.Path(args[args.index('-o')+1])
    data=(root/'source/website/public/updates'/file).read_bytes()
    if mode=='feed-mismatch' and file=='appcast.xml': data=b'different production feed'
    out.write_bytes(data)
'''

class SiteShipTests(unittest.TestCase):
    def run_fixture(self, mode):
        with tempfile.TemporaryDirectory(prefix='volant-site-ship-') as folder:
            root=Path(folder)
            (root/'Scripts').mkdir()
            shutil.copy2(ROOT/'Scripts/ship.sh',root/'Scripts/ship.sh')
            updates=root/'source/website/public/updates'
            updates.mkdir(parents=True)
            (root/'website').mkdir()
            (root/'source/website/components').mkdir()
            (root/'source/website/components/site-chrome.tsx').write_text("export const appVersion = '0.3.33';\n")
            dmg=b'fictional app distribution bytes'
            (updates/'Volant-0.3.33.dmg').write_bytes(dmg)
            (updates/'appcast.xml').write_text('<fictional-signed-feed/>')
            (updates/'SHA256SUMS').write_text(hashlib.sha256(dmg).hexdigest()+'  Volant-0.3.33.dmg\n')
            commands=root/'bin'
            commands.mkdir()
            fake=commands/'fake'
            fake.write_text(FAKE)
            fake.chmod(0o755)
            for name in ['git','gh','curl','npx','npm','sleep']:
                (commands/name).symlink_to(fake)
            env=dict(os.environ,PATH=str(commands)+os.pathsep+os.environ['PATH'],SHIP_FIXTURE=str(root),SHIP_CASE=mode)
            result=subprocess.run(['bash',str(root/'Scripts/ship.sh'),'--site-only'],env=env,text=True,capture_output=True,timeout=20)
            calls=[json.loads(line) for line in (root/'calls').read_text().splitlines()]
            return result,calls

    def test_success_deploys_and_verifies_without_app_release(self):
        result,calls=self.run_fixture('success')
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertIn('Appcast and SHA256SUMS are byte-for-byte unchanged',result.stdout)
        self.assertTrue(any(c[0]=='npx' and 'deploy' in c for c in calls))
        self.assertTrue(any(c[0]=='npm' and 'test:security:production' in c for c in calls))
        self.assertFalse(any(c[0]=='gh' and len(c)>1 and c[1]=='release' for c in calls))

    def test_pending_checks_prevent_deploy(self):
        self.assert_refuses_deploy('pending')

    def test_dirty_checkout_prevents_deploy(self):
        self.assert_refuses_deploy('dirty')

    def test_different_production_feed_prevents_deploy(self):
        self.assert_refuses_deploy('feed-mismatch')

    def assert_refuses_deploy(self,mode):
        result,calls=self.run_fixture(mode)
        self.assertNotEqual(result.returncode,0,result.stdout)
        self.assertIn('nothing published',result.stderr)
        self.assertFalse(any(c[0]=='npx' and 'deploy' in c for c in calls))

if __name__=='__main__':
    unittest.main()
