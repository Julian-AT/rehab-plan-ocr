"""Check the public signing certificate of a copied, privately provisioned app.

Uses Apple's signing tools instead of parsing the Mach-O signature. This is a
local packaging check; target-platform acceptance and fresh revocation evidence
still require their separate release checks.
"""

import datetime
import hashlib
import tempfile
from pathlib import Path


def verify_signer(component, profile, runner, *, now=None):
    allowed = profile.get("DeveloperCertificates")
    if (
        not isinstance(allowed, list)
        or not allowed
        or any(not isinstance(certificate, bytes) or not certificate for certificate in allowed)
    ):
        raise ValueError("Profile has no valid list of authorized signing certificates")
    checked = now or datetime.datetime.now(datetime.timezone.utc)
    if checked.tzinfo is None or checked.utcoffset() is None:
        raise ValueError("Certificate verification requires an explicit timezone")
    checked = checked.astimezone(datetime.timezone.utc)
    with tempfile.TemporaryDirectory(prefix="reha-signing-certificates-") as directory:
        root = Path(directory)
        prefix = root / "signer"
        runner("codesign", "--display", f"--extract-certificates={prefix}", str(component))
        extracted = set(root.glob("signer*"))
        chain = [root / f"signer{index}" for index in range(len(extracted))]
        if (
            not chain
            or set(chain) != extracted
            or any(path.is_symlink() or not path.is_file() for path in chain)
        ):
            raise ValueError("App signature has no complete signing certificate chain")
        certificates = [path.read_bytes() for path in chain]
        if certificates[0] not in allowed:
            raise ValueError(
                "App signing certificate is not authorized by its provisioning profile"
            )
        # System trust anchors remain in use. Never trust an extracted root just
        # because it came from the signature, or fetch missing certificates/OCSP.
        runner(
            "security",
            "verify-cert",
            "-p",
            "codeSign",
            "-L",
            "-R",
            "offline",
            "-N",
            "-d",
            checked.strftime("%Y-%m-%d-%H:%M:%S"),
            *[argument for path in chain for argument in ("-c", str(path))],
        )
    return {
        "certificate_sha256": hashlib.sha256(certificates[0]).hexdigest(),
        "chain_sha256": [hashlib.sha256(value).hexdigest() for value in certificates],
        "authorized_by_profile": True,
        "offline_chain_policy": "codeSign",
        "checked_at_utc": checked.isoformat(),
        "fresh_revocation_status_verified": False,
        "target_platform_acceptance_verified": False,
    }
