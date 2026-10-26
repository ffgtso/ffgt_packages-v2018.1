#!/usr/bin/env python3
"""Run the real shell script against isolated UCI/batctl/hostapd doubles."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'files/usr/lib/ssid-changer/ssid-changer.sh'
DISPATCH = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
root = Path(os.environ['SSID_CHANGER_RUN_DIR'])
state = json.loads((root / 'state.json').read_text())
cmd = Path(sys.argv[0]).name
if cmd == 'uci':
    args = [a for a in sys.argv[1:] if a != '-q']
    if args == ['show', 'wireless']:
        if state.get('uci_error'): sys.exit(1)
        for key in state['radios']:
            print('wireless.' + key + '=wifi-iface')
    else:
        _, section, option = args[1].split('.')
        value = state['radios'].get(section, {}).get(option)
        if value is None: sys.exit(1)
        print(value)
elif cmd == 'batctl':
    if state.get('bat_error'): sys.exit(1)
    print(state['gateway'])
elif cmd == 'uname':
    print(state['hostname'])
elif cmd == 'logger':
    with (root / 'logs').open('a') as f: f.write(repr(sys.argv[1:]) + '\n')
elif cmd == 'killall':
    assert sys.argv[1:] == ['-HUP', 'hostapd']
    snapshot = {p.name: p.read_text() for p in root.glob('hostapd-phy*.conf')}
    with (root / 'reloads').open('a') as f: f.write(json.dumps(snapshot) + '\n')
    sys.exit(1 if state.get('hup_error') else 0)
'''


class ChangerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        bindir = self.root / 'bin'
        bindir.mkdir()
        for name in ('uci', 'batctl', 'uname', 'logger', 'killall'):
            p = bindir / name
            p.write_text(DISPATCH)
            p.chmod(0o755)
        self.env = dict(os.environ, PATH=str(bindir) + ':' + os.environ['PATH'],
                        SSID_CHANGER_RUN_DIR=str(self.root))
        self.state = {'hostname': 'testnode', 'gateway': '=> aa:bb:cc:dd:ee:ff ( 80) via x',
                      'radios': {'client_radio0': {'ifname': 'client0', 'ssid': 'Freifunk'},
                                 'client_radio1': {'ifname': 'client1', 'ssid': 'Freifunk 5G'}}}

    def config(self, radio, ssid, private=False, hex_ssid=False):
        text = f'interface=client{radio}\ndriver=nl80211\n'
        text += ('ssid2=' + ssid.encode().hex() if hex_ssid else 'ssid=' + ssid) + '\n'
        if private:
            text += '\nbss=private0\nssid=Freifunk\nwpa_passphrase=secret&/value\n'
        path = self.root / f'hostapd-phy{radio}.conf'
        path.write_text(text)
        path.chmod(0o600)
        return path

    def run_script(self, expected=0):
        (self.root / 'state.json').write_text(json.dumps(self.state))
        p = subprocess.run([os.environ.get('TEST_SHELL', '/bin/sh'), str(SCRIPT)],
                           env=self.env, capture_output=True, text=True, timeout=10)
        self.assertEqual(p.returncode, expected, p.stdout + p.stderr)
        self.assertFalse((self.root / 'ssid-changer.lock').exists())
        return p

    def reloads(self):
        p = self.root / 'reloads'
        return [json.loads(x) for x in p.read_text().splitlines()] if p.exists() else []

    def test_first_radio_correct_second_offline(self):
        self.config(0, 'Freifunk')
        p = self.config(1, 'FF_OFFLINE_testnode')
        self.run_script()
        self.assertIn('ssid=Freifunk 5G\n', p.read_text())
        self.assertEqual(len(self.reloads()), 1)

    def test_second_correct_does_not_cancel_reload(self):
        self.config(0, 'FF_OFFLINE_testnode')
        self.config(1, 'Freifunk 5G')
        self.run_script()
        self.assertEqual(len(self.reloads()), 1)

    def test_both_radios_updated_before_single_reload(self):
        self.config(0, 'Freifunk')
        self.config(1, 'Freifunk 5G')
        self.state['gateway'] = '* aa ( 44) via x'
        self.run_script()
        snapshots = self.reloads()
        self.assertEqual(len(snapshots), 1)
        self.assertTrue(all('ssid=FF_OFFLINE_testnode\n' in x for x in snapshots[0].values()))

    def test_hysteresis_including_boundaries(self):
        for tq in (45, 50, 55):
            with self.subTest(tq=tq):
                p = self.config(0, 'FF_OFFLINE_testnode')
                before = p.read_bytes()
                self.state['gateway'] = f'=> aa ({tq}) via x'
                self.run_script()
                self.assertEqual(p.read_bytes(), before)
        self.assertEqual(self.reloads(), [])

    def test_upper_boundary_plus_one(self):
        p = self.config(0, 'FF_OFFLINE_testnode')
        self.state['gateway'] = '  => aa (56) via x'
        self.run_script()
        self.assertIn('ssid=Freifunk\n', p.read_text())

    def test_no_selected_gateway(self):
        p = self.config(0, 'Freifunk')
        self.state['gateway'] = '[B.A.T.M.A.N. adv]\n aa (255) via x\nNo gateways in range ...'
        self.run_script()
        self.assertIn('ssid=FF_OFFLINE_testnode\n', p.read_text())

    def test_empty_table(self):
        p = self.config(0, 'Freifunk')
        self.state['gateway'] = ''
        self.run_script()
        self.assertIn('ssid=FF_OFFLINE_testnode\n', p.read_text())

    def test_gateway_command_failure(self):
        p = self.config(0, 'Freifunk')
        before = p.read_bytes()
        self.state['bat_error'] = True
        self.run_script(expected=1)
        self.assertEqual(p.read_bytes(), before)
        self.assertEqual(self.reloads(), [])

    def test_invalid_gateway_values(self):
        p = self.config(0, 'Freifunk')
        before = p.read_bytes()
        for row in ('=> aa (bad)', '=> aa (256)', '=> aa (-1)',
                    '=> aa (10.5 MBit)', '=> aa (20)\n* bb (80)'):
            with self.subTest(row=row):
                self.state['gateway'] = row
                self.run_script(expected=1)
                self.assertEqual(p.read_bytes(), before)
        self.assertEqual(self.reloads(), [])

    def test_special_characters_are_literal(self):
        for ssid in ('FF /a&b[.*]=$x\\end', 'FF\ttab=ssid', ' space trailing '):
            with self.subTest(ssid=ssid):
                self.state['radios']['client_radio0']['ssid'] = ssid
                p = self.config(0, 'FF_OFFLINE_old_hostname')
                self.run_script()
                self.assertIn('ssid=' + ssid + '\n', p.read_text())

    def test_private_bss_same_ssid_untouched(self):
        p = self.config(0, 'Freifunk', private=True)
        private = p.read_text().split('bss=private0')[1]
        self.state['gateway'] = '=> aa (0)'
        self.run_script()
        self.assertEqual(p.read_text().split('bss=private0')[1], private)
        self.assertEqual(p.stat().st_mode & 0o777, 0o600)

    def test_client_is_secondary_bss(self):
        p = self.root / 'hostapd-phy0.conf'
        p.write_text('interface=private0\nssid=Private\nbss=client0\nssid=Old\n')
        self.run_script()
        self.assertEqual(p.read_text(), 'interface=private0\nssid=Private\nbss=client0\nssid=Freifunk\n')

    def test_ssid2_supported(self):
        p = self.config(0, 'Old', hex_ssid=True)
        self.run_script()
        self.assertIn('ssid=Freifunk\n', p.read_text())
        self.assertNotIn('ssid2=', p.read_text())

    def test_idempotent(self):
        self.config(0, 'Old')
        self.run_script()
        self.run_script()
        self.assertEqual(len(self.reloads()), 1)

    def test_no_hostapd_files(self):
        self.run_script()
        self.assertEqual(self.reloads(), [])

    def test_long_hostname_limit(self):
        p = self.config(0, 'Freifunk')
        self.state['hostname'] = 'abcdefghij' * 6
        self.state['gateway'] = '=> aa (0)'
        self.run_script()
        ssid = next(x[5:] for x in p.read_text().splitlines() if x.startswith('ssid='))
        self.assertEqual(len(ssid.encode()), 32)
        self.assertTrue(ssid.startswith('FF_OFFLINE_abcdefghi...'))
        self.assertTrue(ssid.endswith('bcdefghij'))

    def test_missing_uci_ssid_does_not_invent_freifunk(self):
        p = self.config(0, 'Custom')
        del self.state['radios']['client_radio0']['ssid']
        self.run_script()
        self.assertIn('ssid=Custom\n', p.read_text())
        self.assertEqual(self.reloads(), [])

    def test_empty_uci_map(self):
        p = self.config(0, 'Custom')
        self.state['radios'] = {}
        self.run_script()
        self.assertIn('ssid=Custom\n', p.read_text())
        self.assertEqual(self.reloads(), [])

    def test_invalid_online_ssid(self):
        p = self.config(0, 'Custom')
        for ssid in ('', 'x' * 33, 'a\nb'):
            self.state['radios']['client_radio0']['ssid'] = ssid
            self.run_script()
            self.assertIn('ssid=Custom\n', p.read_text())
        self.assertEqual(self.reloads(), [])

    def test_failed_hup_retried_inside_hysteresis(self):
        self.config(0, 'Old')
        self.state['hup_error'] = True
        self.run_script(expected=1)
        self.assertTrue((self.root / 'ssid-changer.reload').exists())
        self.state['hup_error'] = False
        self.state['gateway'] = '=> aa (50)'
        self.run_script()
        self.assertEqual(len(self.reloads()), 2)
        self.assertFalse((self.root / 'ssid-changer.reload').exists())

    def test_lock_blocks_second_instance(self):
        (self.root / 'ssid-changer.lock').mkdir()
        p = subprocess.run(['/bin/sh', str(SCRIPT)], env=self.env, timeout=10)
        self.assertEqual(p.returncode, 0)
        self.assertEqual(self.reloads(), [])
        self.assertTrue((self.root / 'ssid-changer.lock').exists())

    def test_uci_failure(self):
        p = self.config(0, 'Custom')
        self.state['uci_error'] = True
        self.run_script(expected=1)
        self.assertIn('ssid=Custom\n', p.read_text())
        self.assertEqual(self.reloads(), [])


if __name__ == '__main__':
    unittest.main(verbosity=2)
