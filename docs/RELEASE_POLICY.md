# ShopOS Release Policy

Every pull request to `main` must pass the complete test suite and produce a verified candidate image. The merge job receives write permission only after the read-only test and image jobs succeed, and it refuses to merge if the reviewed head commit changed.

Every successful merge to `main` starts a second production build from the exact final commit. That build reruns tests, creates a fresh Raspberry Pi image, verifies its checksum and emits JSON provenance plus a CycloneDX SBOM foundation. Candidate artifacts are short-lived; production artifacts use the final `main` commit in their name and receive longer retention.

A successful CI build is not by itself a general-availability release. Production distribution additionally requires the open gates in `PRODUCTION_READINESS.md`, including signed metadata, root-filesystem vulnerability scanning, rollback-capable updates, tested restore and physical-device validation.

Release channels:

- `development`: no compatibility promise;
- `candidate`: CI-valid image for automated and laboratory testing;
- `pilot`: supervised installations with a documented recovery path;
- `production`: all mandatory readiness evidence closed for the exact artifact.

No image may be relabelled from one channel to another. A production image must be rebuilt from the final production commit and retain its original checksum and provenance.
