# Release Signing & Notarization

Open Island Reimagine uses two independent trust layers.

| Layer | Purpose | Required now |
|---|---|---|
| Sparkle EdDSA | Proves an automatic-update ZIP belongs to Reimagine | **Yes; release fails when missing** |
| Apple Developer ID + notarization | Lets macOS trust the app without a first-open warning | Optional until Apple credentials are configured |

5 岁版：Sparkle 钥匙证明“新玩具是我们自己装进盒子的”；Apple 印章证明“苹果也检查过这个盒子”。现在第一把钥匙已经必须使用，苹果印章可以以后再补。

## Secret rules

- Private keys and certificates belong only in macOS Keychain or GitHub Actions
  Secrets.
- Never commit `.p12`, `.pem`, `.p8`, private-key exports, passwords, or secret
  environment files.
- The public EdDSA key is intentionally committed in `config/release.env` and
  embedded into the app.

## Required GitHub secret for automatic updates

| Secret | Description |
|---|---|
| `SPARKLE_EDDSA_KEY` | Reimagine Sparkle private EdDSA key. The Release workflow signs `Open Island.zip` with it. |

If this secret is absent or signing produces an empty result, the Release
workflow stops before publishing update metadata.

## Optional Apple secrets

| Secret | Description |
|---|---|
| `APPLE_CERTIFICATE_P12` | Base64 Developer ID Application identity |
| `APPLE_CERTIFICATE_PASSWORD` | Password for the P12 |
| `APPLE_SIGNING_IDENTITY` | `Developer ID Application: ...` identity name |
| `APPLE_ID` | Apple ID used for notarization |
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific notarization password |

When these are absent, CI uses an ad-hoc app signature. Users may need to
right-click the app and choose **Open** on first launch. Sparkle EdDSA signing
still remains mandatory.

## Release flow

1. Merge the reviewed version/config change to `main`.
2. Push the exact canonical tag from `config/release.env`.
3. The workflow packages and validates the app.
4. It signs the update ZIP with `SPARKLE_EDDSA_KEY`.
5. It publishes the GitHub Release before updating the appcast.
6. The appcast update is merged through its own CI-checked PR.

See [releasing.md](releasing.md) for the bridge-install boundary and acceptance checklist.
