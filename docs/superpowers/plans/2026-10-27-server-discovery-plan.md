# Server discovery implementation

1. Reuse saved server identity and recovery; gate startup/manual saved-user sign-in on verification and preserve accounts on network failure.
2. Add state-based discovery presentation on iPhone/iPad/TV; bounded scan lifecycle, retry and manual fallback UI.
3. Normalize bare addresses with default port; provide optional verified alternate-address settings with responsive layout.
4. Test normalization and mismatched identities using pure Swift, parse changed Swift, run existing local checks and review focused diff.
5. Submit PR with explicit physical-device and Apple multicast entitlement release dependencies; do not claim TestFlight release.

Implementation complete locally. Checks: pure Swift policies, existing quick checks, Swift syntax parse and whitespace pass; SwiftLint has warnings only. Full application compilation, simulator interaction, physical local-network discovery and TestFlight upload remain unverified in the restricted runtime.
