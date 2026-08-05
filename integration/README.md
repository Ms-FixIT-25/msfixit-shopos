This branch is the combined ShopOS integration candidate.

Release flow:

1. Run the complete repository and integrated ShopOS test suites.
2. Build a fresh Raspberry Pi 4 USB image on a native ARM64 runner.
3. Verify the generated SHA-256 checksum and preserve build provenance.
4. Upload the tested image as a workflow artifact.
5. Squash-merge the exact tested head commit into `main` automatically.

Any failed test, failed image build, checksum mismatch, changed head commit, draft pull request, or external fork blocks the merge.
