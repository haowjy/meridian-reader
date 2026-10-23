# Releasing Meridian Reader

Manual release process. Main holds release versions and is pushed to GitHub.

## Development process

Single-lane: one feature branch at a time off main → push → PR (body from the template at
`.github/pull_request_template.md`) → merge into main → delete the branch. No parallel worktrees.

The PR body is the technical changelog (Added/Changed/Fixed/Removed lines). A release's
user-facing text lives in `release-notes/<version>.md`.

## Cutting a release

### TestFlight

1. Add `release-notes/<version>.md` with user-facing bullets (see `release-notes/README.md`).
2. Commit and push to main.
3. In GitHub → Actions → Release, click *Run workflow*:
   - **version**: the semver string (e.g. `0.1.0`).
   - **target**: *TestFlight*.
   - **dry_run**: true first to verify, then false.
4. The workflow generates WhatsNew.json, archives, uploads to TestFlight, commits the version
   bump, tags `vX.Y.Z` and creates a GitHub Release with the notes.
5. In App Store Connect, paste the release notes into What to Test for the build (the ASC API
   can automate this later).

### App Store

Same as TestFlight, but pick *App Store submit* as the target. The build uploads to App Store
Connect; submit for review manually there (the build takes 5–30 minutes to process). Paste the
release notes into What's New for the version in App Store Connect.

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
4. **Privacy policy URL** and **Support URL**: required by Apple. Hosted on GitHub Pages from
   `site/` in this repo:
   - Privacy: https://haowjy.github.io/meridian-reader/privacy.html
   - Support: https://haowjy.github.io/meridian-reader/support.html
   Paste both into App Store Connect › App Information. Settings in the app also links to them.
5. **Screenshots**: iPhone 6.7" and 6.1" sets, plus iPad 12.9"/13" portrait (`TARGETED_DEVICE_FAMILY = 1,2`). Framed previews live under `~/.meridian/.../work/release/screenshots/app-store/` (not in this repo).
6. **Age rating**: answer the questionnaire (no objectionable content).
7. **Export compliance**: the app declares `ITSAppUsesNonExemptEncryption = NO` in Info.plist,
   so Apple skips the export compliance question on each submission.

## Third-party licenses

| Package | License | Notes |
|---------|---------|-------|
| Kokoro (via FluidAudio) | Apache-2.0 | The ONNX model is downloaded at runtime into Application Support from Hugging Face (`KokoroONNXModelStore`), never bundled in the app. |
| FluidAudio | Apache-2.0 | Vendored with local patches (`Vendor/FluidAudio/VENDORED.md`). |
| Phonon / Gradium (ptts) | Apache-2.0 / MIT | Phonon 31m English Core ML; zip downloaded at runtime (~131 MB). |
| ONNX Runtime | MIT | Swift package, CPU inference only. |
| ZIPFoundation | MIT | EPUB and Phonon model unzip. |
| Mozilla Readability | Apache-2.0 | Bundled JS under `Resources/Readability/`. |

All licenses are permissive (Apache-2.0, MIT) and compatible with App Store distribution.
Settings › About › Acknowledgements lists them in-app. No separate license file is in the repo
(owner decision).
