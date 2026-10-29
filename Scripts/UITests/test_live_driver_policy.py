"""Offline credential-policy checks. No server connection or content mutation."""
import contextlib
import io
import unittest
from unittest.mock import patch
import live_jellyfin_driver as driver

class RestrictedAccountTests(unittest.TestCase):
    def check_policy(self, policy):
        driver.CONFIG = {'url': 'http://example.invalid', 'serverId': 'expected', 'keychainService': 'test', 'username': 'test'}
        responses = [{'Id': 'expected'}, {'AccessToken': 'test-token'}, {'Id': 'test-user', 'Policy': policy}]
        with patch.object(driver, 'request', side_effect=responses), patch.object(driver.subprocess, 'check_output', return_value='test-password'), contextlib.redirect_stdout(io.StringIO()):
            driver.authenticate()

    def test_restricted_account_is_accepted(self):
        self.check_policy({'IsAdministrator': False, 'EnableContentDeletion': False, 'EnableContentDeletionFromFolders': []})

    def test_unsafe_or_missing_policy_is_rejected(self):
        for policy in [{}, {'IsAdministrator': True}, {'IsAdministrator': False, 'EnableContentDeletion': True}, {'IsAdministrator': False, 'EnableContentDeletion': False, 'EnableContentDeletionFromFolders': ['folder']}]:
            with self.subTest(policy=policy), self.assertRaises(RuntimeError):
                self.check_policy(policy)

    def test_server_identity_mismatch_is_rejected_before_credentials(self):
        driver.CONFIG = {'url': 'http://example.invalid', 'serverId': 'expected'}
        with patch.object(driver, 'request', return_value={'Id': 'unexpected'}), patch.object(driver.subprocess, 'check_output') as keychain:
            with self.assertRaises(RuntimeError):
                driver.authenticate()
            keychain.assert_not_called()

if __name__ == '__main__':
    unittest.main()
