#!/usr/bin/env python3
"""Check registered App Group authorization in exported macOS bundles."""

import fnmatch
from pathlib import Path
import plistlib
import subprocess
import sys


def validate_profile(entitlements, profile):
    groups = [
        group for group in entitlements.get("com.apple.security.application-groups", [])
        if group.startswith("group.")
    ]
    if not groups:
        return  # Historical releases use unprovisioned Team ID-prefixed groups.
    if profile is None:
        raise ValueError("registered App Group requires an embedded provisioning profile")

    authorization = profile.get("Entitlements", {})
    app_id = entitlements.get("com.apple.application-identifier")
    allowed_app_id = authorization.get("com.apple.application-identifier", "")
    if not app_id or not fnmatch.fnmatchcase(app_id, allowed_app_id):
        raise ValueError("signed application identifier is missing or does not match the profile")

    allowed_groups = authorization.get("com.apple.security.application-groups", [])
    for group in groups:
        if not any(fnmatch.fnmatchcase(group, allowed) for allowed in allowed_groups):
            raise ValueError(f"profile does not authorize App Group {group}")


def read_command_plist(command):
    result = subprocess.run(command, check=True, capture_output=True)
    return plistlib.loads(result.stdout)


def verify_bundle(bundle):
    entitlements = read_command_plist([
        "codesign", "-d", "--entitlements", ":-", str(bundle),
    ])
    profile_path = bundle / "Contents" / "embedded.provisionprofile"
    profile = None
    if profile_path.is_file():
        profile = read_command_plist(["security", "cms", "-D", "-i", str(profile_path)])
    validate_profile(entitlements, profile)
    print(f"App Group authorization verified: {bundle.name}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("Usage: verify-app-group-profiles.py APP_BUNDLE [EXTENSION_BUNDLE ...]")
    for argument in sys.argv[1:]:
        try:
            verify_bundle(Path(argument))
        except (ValueError, OSError, subprocess.CalledProcessError) as error:
            sys.exit(f"{argument}: {error}")
