# Release Signing & Notarization

Open Island Reimagine uses two independent trust layers.

| Layer | Purpose | Required now |
|---|---|---|
| Sparkle EdDSA | Proves an automatic-update ZIP belongs to Reimagine | **Yes; release fails when missing** |
| Stable Reimagine self-signed identity | Keeps the same macOS TCC/Accessibility identity between builds | **Yes for the Reimagine release line** |
| Apple Developer ID + notarization | Lets macOS trust the app without a first-open warning | Optional paid upgrade |

5 岁版：Sparkle 钥匙证明“新玩具是我们自己装进盒子的”；稳定签名像一张一直不换的学生证，所以 Mac 不会每次都把它当成陌生小朋友；Apple 印章则表示“苹果也检查过这个盒子”，以后需要时再付费办理。

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

## Required stable-signing secrets

| Secret / variable | Description |
|---|---|
| `REIMAGINE_CERTIFICATE_P12` | Base64 of the protected self-signed identity; never commit it |
| `REIMAGINE_CERTIFICATE_PASSWORD` | Password protecting that P12 |
| `REIMAGINE_SIGNING_IDENTITY` | `Open Island Reimagine Stable` |
| Repository variable `REIMAGINE_SIGNING_MODE` | `self-signed` |

The local and CI package must use the exact same certificate. Run
`scripts/setup-release-signing.sh` only for the initial creation. Keep one
encrypted offline backup of the P12; losing it would require another one-time
Accessibility permission migration.

The local protected backup lives outside the repository. Its password belongs
in macOS Keychain, never in shell history, documentation, Git, or CI logs.

## Optional Apple secrets

| Secret | Description |
|---|---|
| `APPLE_CERTIFICATE_P12` | Base64 Developer ID Application identity |
| `APPLE_CERTIFICATE_PASSWORD` | Password for the P12 |
| `APPLE_SIGNING_IDENTITY` | `Developer ID Application: ...` identity name |
| `APPLE_ID` | Apple ID used for notarization |
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific notarization password |

The stable self-signed identity is not Apple Developer ID and cannot be
notarized. Users may still need to right-click the app and choose **Open** on
first launch. Sparkle EdDSA signing remains mandatory and independently proves
the update ZIP belongs to Reimagine.

Because a self-signed certificate has no Apple Team ID, Reimagine packages use
`OpenIslandApp.self-signed.entitlements` to disable only Hardened Runtime's
Team-ID library validation. This lets the separately signed embedded
`Sparkle.framework` load at startup. Developer ID packages continue to use the
regular entitlement file and keep library validation enabled.

5 岁版：我们自己的学生证没有苹果学校的班级号。Mac 如果硬要比班级号，就会把主程序和 Sparkle 小帮手挡在门外。自签名版本只关掉这一次“比班级号”，其他门锁继续保留；以后换成苹果正式学生证，就重新打开这道检查。

## Release flow

1. Merge the reviewed version/config change to `main`.
2. Push the exact canonical tag from `config/release.env`.
3. The workflow packages, signs, and launches the final signed app for three
   seconds. A launch-time Sparkle or entitlement failure stops the release.
4. It signs the update ZIP with `SPARKLE_EDDSA_KEY`.
5. It publishes the GitHub Release before updating the appcast.
6. The appcast update is merged through its own CI-checked PR.

See [releasing.md](releasing.md) for the bridge-install boundary and acceptance checklist.
