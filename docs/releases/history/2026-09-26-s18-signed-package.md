> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Signed private package — 2026-09-26

Historical record of technical packaging, not release or installation approval.
No physical device was updated.

`make build TARGET=archive` succeeds at source
`21ff05479c434c84a3e10814bfbf025b5ea7d612`. The archive contains version 0.3.0,
build 2026092625, with the existing app/extension identifiers and iOS 26.0 minimum.
The verifier checks all four signatures, App Groups, provisioning profiles,
bundled models/dictionary, privacy manifests and 15 dependency notices. One
device is authorized by all four profiles. Public distribution remains uncleared.

The IPA is 340,933,354 bytes, SHA-256
`a6b39513bed1abfe85ba1deea93cb77563cb23e9a1f5e9696b3a03e258abb2d9`.
The earliest profile expires **2026-09-26 at 11:56:33 UTC** (13:56:33 in Vienna).
Reverify and renew signing as necessary before any subsequently approved update;
this successful check does not establish later installability.

The archive's 79 files and IPA were copied to ignored private storage and verified
against source hashes before and after copying. The preceding package report is
also retained. Evidence: `.local/runs/signed-package-20260926-s18-001`.
Verification report SHA-256:
`a6eeaf09f599ad5cf6ef2da63d4e49e4b5e901913dc326a06033b1820373a217`.
Run receipt SHA-256:
`7835092219af1d7d71973bfdfffed47f4aae8dd0ca62ce3b2be5912677667483`.

Full hosted CI, visual and model qualification, human listening and physical
acceptance remain open. Preview/listening approval and a fresh complete backup
are still required before an in-place device update.
