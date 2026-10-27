# Local validation

Validation runs on your Mac; GitHub Actions is not used. Xcode, its command-line tools, and installed iPhone, iPad, and Apple TV simulators are required for the full run. Package resolution may need Internet access on the first build.

Run all checks and simulator tests from the repository:

```sh
bash Scripts/Checks/validate-local.sh
```

Run only playback, Top Shelf artwork, paging, PIN, transport configuration, and whitespace checks:

```sh
bash Scripts/Checks/validate-local.sh --quick
```

The full run selects an available simulator for each device family and runs the shared iOS scheme on both iPhone and iPad, followed by the tvOS test scheme. It stops on failure. Logs and Xcode result bundles are saved in a timestamped temporary directory printed at startup. Set `WATERMELONFIN_RESULTS_DIR` to a new directory to choose the location yourself. Open an `.xcresult` bundle in Xcode to inspect failures and UI-test screenshots.

These commands do not sign a distribution build, upload TestFlight builds, or publish the website. Remote-control interaction and physical-device release checks remain separate.
