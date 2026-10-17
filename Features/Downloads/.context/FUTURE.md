# Downloads: deferred

- **Rendering while charging, with the phone locked** (D16 says downloads render "mainly in the
  foreground or while charging"). Not built: with the app in the background, download jobs park
  like any article that isn't playing. It needs a `BGProcessingTask` with
  `requiresExternalPower` (Info.plist `BGTaskSchedulerPermittedIdentifiers`, the `processing`
  background mode), registered at launch, that admits download jobs on the ONNX route only (never
  Core ML), one ONNX thread, while nothing plays, and stops at expiry. The launch it may cause runs
  in the background (library maintenance, the Kokoro load), which nothing has been measured for
  yet. Ties in with Speech's deferred overnight baking (`../../Speech/.context/FUTURE.md`). Needs a
  Release build and a locked, charging phone to verify (timing log).
- A *Keep* is per download: after a second voice change the kept voice is still accepted.
- Storage is measured per download from its pages' audio folders; pages shared by two downloads
  count in both.
