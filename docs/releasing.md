# Releasing Open Island Reimagine

The Reimagine release line owns its version, GitHub assets, Sparkle appcast and
EdDSA signing key. `config/release.env` is the single source of truth.

## Release identity

The canonical file defines:

- user-facing version (`REIMAGINE_VERSION`)
- monotonic numeric build (`REIMAGINE_BUILD_NUMBER`)
- production bundle ID (`app.openisland.dev`, retained for settings and TCC continuity)
- Reimagine appcast and Releases URLs
- the public Sparkle EdDSA key

Run this before every release:

```bash
zsh scripts/check-release-config.sh
```

The git tag must be exactly `v$REIMAGINE_VERSION`. A release with a mismatched
tag, missing Sparkle private key, invalid package identity, or stale upstream
update URL fails closed.

## First migration from the old custom build

The installed `0.1.0` custom build contains the old publisher's Sparkle public
key. A signed updater cannot silently replace that trusted key. Therefore the
first move to `1.1.6-reimagine.30` is a **one-time manual bridge install**:

1. Quit Open Island.
2. Keep a rollback copy of the existing app.
3. Replace `/Applications/Open Island.app` with the verified Reimagine package.
4. Launch it once and confirm the C/G/W/O chips and session workflow.

The production bundle ID stays the same, so the existing settings and macOS
privacy identity can continue. From the bridged version onward, Sparkle reads
only the Reimagine appcast and accepts only packages signed by the Reimagine
key.

## Automated release flow

1. Update `config/release.env` in a reviewed PR. The numeric build must always
   increase.
2. Run:

   ```bash
   zsh scripts/harness.sh lint
   OPEN_ISLAND_SKIP_DMG=true zsh scripts/package-app.sh
   ```

3. Merge the PR to `main` and create the exact canonical tag:

   ```bash
   source config/release.env
   git tag "v$REIMAGINE_VERSION"
   git push origin "v$REIMAGINE_VERSION"
   ```

4. GitHub Actions builds the app, verifies its Info.plist identity, signs the
   ZIP with the `SPARKLE_EDDSA_KEY` secret, publishes the Release, and only then
   adds the signed item to `appcast.xml` through an automated PR.
5. Verify the Release assets are downloadable before accepting the appcast PR
   result.

## Sparkle feed

Canonical feed:

```text
https://raw.githubusercontent.com/leeyf2018/Openisland-Reimagine/main/appcast.xml
```

Canonical release assets:

```text
https://github.com/leeyf2018/Openisland-Reimagine/releases
```

Each appcast item must contain the same version/build as `config/release.env`,
the exact Release ZIP length, and a valid EdDSA signature. Never paste the
private key into a file, workflow log, issue, or commit.

## Acceptance

- `scripts/check-release-config.sh` passes.
- Harness and package verification checks are green on the release commit.
- Packaged Info.plist matches the canonical bundle ID, version, build, feed and
  public key.
- Release ZIP exists before its appcast item is merged.
- The ZIP signature verifies with Sparkle tooling.
- After the one-time bridge install, C/G/W/O and session business functions are
  still present.

Apple Developer ID notarization is a separate trust layer. When Apple secrets
are absent, the Release may be ad-hoc signed and require right-click → Open;
this does not weaken the Sparkle EdDSA package signature.
