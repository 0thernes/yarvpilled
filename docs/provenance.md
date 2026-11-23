# Release provenance

Each `v*` tag runs `.github/workflows/release.yml`, which builds these assets on a
GitHub-hosted runner from the tagged commit:

| asset | what |
|---|---|
| `yarvpilled-X.Y.Z.gem` | the gem (`gem build yarvpilled.gemspec`) |
| `yarvpilled-X.Y.Z-src.tar.gz` | `git archive` of the tag |
| `yarvpilled-X.Y.Z-bench.json`, `-control.json` | the recorded data behind the README numbers |
| `SHA256SUMS` | SHA-256 of every asset above |

It then signs a [SLSA build provenance](https://slsa.dev/provenance) attestation for every
asset with `actions/attest-build-provenance` (Sigstore, keyless, tied to this repository's
workflow run). The attestation says: this exact file was built by this workflow, from this
commit, in this repository.

## Verify a download

```sh
v=0.4.0
gh release download "v$v" -R 0thernes/yarvpilled -D yarvpilled-$v && cd yarvpilled-$v

# 1. integrity: the files match the published checksums
sha256sum -c SHA256SUMS

# 2. provenance: each file was built by this repo's release workflow
for f in yarvpilled-$v*; do gh attestation verify "$f" -R 0thernes/yarvpilled; done

# 3. the source archive is the tagged commit
git -C /path/to/clone archive --format=tar.gz --prefix="yarvpilled-$v/" "v$v" | sha256sum
grep src.tar.gz SHA256SUMS
```

Step 3 should print the same hash twice if your `git` produces the same gzip stream (git's
built-in gzip is deterministic for a given git version; a different version can differ in
compression only, in which case compare `tar -tvf` listings instead).

`gh attestation verify` needs GitHub CLI 2.49+. Without `gh`, the attestation is also
visible under the repository's **Attestations** tab and can be checked with
`cosign verify-blob-attestation`.

Releases before v0.4.0 have no assets or attestations.
