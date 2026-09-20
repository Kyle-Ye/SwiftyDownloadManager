import importlib.util
from pathlib import Path
import unittest


spec = importlib.util.spec_from_file_location(
    "app_group_profiles", Path(__file__).parents[1] / "verify-app-group-profiles.py"
)
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


class AppGroupProfilesTest(unittest.TestCase):
    def setUp(self):
        self.entitlements = {
            "com.apple.application-identifier": "TEAM.test.sdm.extension",
            "com.apple.security.application-groups": ["group.test.sdm"],
        }
        self.profile = {"Entitlements": dict(self.entitlements)}

    def test_accepts_profile_authorizing_application_and_group(self):
        verifier.validate_profile(self.entitlements, self.profile)

    def test_rejects_missing_extension_profile(self):
        with self.assertRaisesRegex(ValueError, "embedded provisioning profile"):
            verifier.validate_profile(self.entitlements, None)

    def test_rejects_missing_signed_application_identifier(self):
        del self.entitlements["com.apple.application-identifier"]
        with self.assertRaisesRegex(ValueError, "application identifier"):
            verifier.validate_profile(self.entitlements, self.profile)

    def test_rejects_profile_for_a_different_application(self):
        self.profile["Entitlements"]["com.apple.application-identifier"] = "TEAM.other.app"
        with self.assertRaisesRegex(ValueError, "application identifier"):
            verifier.validate_profile(self.entitlements, self.profile)

    def test_rejects_profile_without_registered_group(self):
        self.profile["Entitlements"]["com.apple.security.application-groups"] = ["TEAM.*"]
        with self.assertRaisesRegex(ValueError, "does not authorize App Group"):
            verifier.validate_profile(self.entitlements, self.profile)

    def test_preserves_historical_unprovisioned_releases(self):
        verifier.validate_profile({}, None)
        verifier.validate_profile({
            "com.apple.security.application-groups": ["TEAM.test.sdm"],
        }, None)


if __name__ == "__main__":
    unittest.main()
