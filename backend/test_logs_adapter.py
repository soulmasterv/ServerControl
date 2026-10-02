import tempfile
import unittest
from pathlib import Path
from logs_adapter import LogsAdapter, redact

class LogsTests(unittest.TestCase):
    def test_allowlist_auth_redaction_and_bounded_tail(self):
        with tempfile.TemporaryDirectory() as temp:
            p = Path(temp) / 'stdout.log'
            p.write_text('normal\n' * 700 + 'Authorization: Bearer private-sentinel\n')
            a = LogsAdapter(log_roots=[temp], processes={1: {'stdout': p}})
            self.assertEqual(a.handle('GET', '/api/process/1/logs')[0], 401)
            self.assertEqual(a.handle('GET', '/api/process/2/logs', authenticated=True)[0], 404)
            self.assertEqual(a.handle('POST', '/api/process/1/logs', authenticated=True)[0], 404)
            status, data = a.handle('GET', '/api/process/1/logs', authenticated=True, limit=99999)
            self.assertEqual(status, 200)
            self.assertEqual(len(data['lines']), 500)
            self.assertTrue(data['truncated'])
            self.assertNotIn('private-sentinel', str(data))
            self.assertEqual(a.handle('GET', '/api/process/../../logs', authenticated=True)[0], 404)

    def test_outside_root_rejected_and_secret_fields_removed(self):
        with tempfile.TemporaryDirectory() as temp, tempfile.TemporaryDirectory() as outside:
            p = Path(outside) / 'secret'; p.write_text('secret')
            with self.assertRaises(ValueError): LogsAdapter(log_roots=[temp], processes={1: {'stdout': p}})
        self.assertNotIn('sentinel', redact('api_key=sentinel password=sentinel Bearer sentinel'))

    def test_docker_only_registered_reader(self):
        a = LogsAdapter(docker_readers={'approved': lambda limit: [{'stream': 'stderr', 'text': 'Billing blocked'}]})
        self.assertEqual(a.handle('GET', '/api/docker/other/logs', authenticated=True)[0], 404)
        status, data = a.handle('GET', '/api/docker/approved/logs', authenticated=True)
        self.assertEqual(status, 200)
        self.assertEqual(data['lines'][0]['stream'], 'stderr')

if __name__ == '__main__': unittest.main()
