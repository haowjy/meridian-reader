# Releasing Meridian Reader

Manual release process. Main holds release versions and is pushed to GitHub.

## Cutting a release

### TestFlight

1. Update CHANGELOG.md: move Unreleased entries into a `## [X.Y.Z] - YYYY-MM-DD` section.
   Write a `### What's New` subsection with user-facing bullets.
2. Commit and push to main.
3. In GitHub → Actions → Release, click *Run workflow*:
   - **version**: the semver string (e.g. `1.0.0`).
   - **target**: *TestFlight*.
   - **dry_run**: true first to verify, then false.
4. The workflow archives, uploads to TestFlight, commits the version bump and WhatsNew.json,
   tags `vX.Y.Z` and creates a GitHub Release with the notes.

### App Store

Same as TestFlight, but pick *App Store submit* as the target. The build uploads to App Store
Connect; submit for review manually there (the build takes 5–30 minutes to process).

### GitHub Release only

Pick *GitHub Release only* to tag and release without uploading to App Store Connect. Useful
for source-only milestones.

## Secrets to add

In the repo's Settings → Secrets and variables → Actions, add:

| Secret | What | How to create |
|--------|------|---------------|
| `ASC_KEY_ID` | App Store Connect API Key ID | App Store Connect → Users and Access → Integrations → App Store Connect API → Generate Key (role: App Manager). Copy the Key ID. |
| `ASC_ISSUER_ID` | The Issuer ID shown on the same API Keys page | Copy from the page header. |
| `ASC_KEY_P8` | Contents of the `.p8` private key file | Download the `.p8` when you create the key (it can only be downloaded once). Paste the full contents including `-----BEGIN PRIVATE KEY-----` lines. |

The workflow uses automatic code signing with the ASC API key
(`-allowProvisioningUpdates -authenticationKeyPath`), so no .p12 certificate or provisioning
profile is needed as a secret — Xcode Cloud–style signing handles it.

## One-time setup in App Store Connect

Before the first submission:

1. **App record**: create the app for bundle ID `com.jimmyyao.Reader`, team JMYU8K3WZN.
2. **Price**: Free.
3. **App Privacy**: "Data Not Collected" (the app has no analytics, no network to our servers,
   no tracking). Answer the privacy questions accordingly.
4. **Privacy policy URL**: required by Apple. Set up a simple page (GitHub Pages or similar)
   and enter its URL in App Store Connect.
5. **Screenshots**: at least one set for 6.7" and 6.1" displays.
6. **Age rating**: answer the questionnaire (no objectionable content).
7. **Export compliance**: the app declares `ITSAppUsesNonExemptEncryption = NO` in Info.plist,
   so Apple skips the export compliance question on each submission.

## Third-party licenses

| Package | License | Notes |
|---------|---------|-------|
| Kokoro (via FluidAudio) | Apache-2.0 | The ONNX model is downloaded at runtime into Application Support from Hugging Face (`KokoroONNXModelStore`), never bundled in the app. |
| FluidAudio | Apache-2.0 | Vendored with local patches (`Vendor/FluidAudio/VENDORED.md`). |
| ONNX Runtime | MIT | Swift package, CPU inference only. |
| ZIPFoundation | MIT | EPUB unzip. |

All licenses are permissive (Apache-2.0, MIT) and compatible with App Store distribution.
No license file is included in the repo (owner decision).
