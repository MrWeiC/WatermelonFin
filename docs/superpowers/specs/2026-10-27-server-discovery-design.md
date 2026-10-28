# Server discovery and address recovery

User-approved intent: users on iPhone, iPad and Apple TV should not spend time looking up Jellyfin addresses. Decisions depend on saved-server state, not an installation's first-launch flag. Tailscale is optional and can be added later.

- No saved servers on launch, or deleting the last server: open discovery. Closing it is allowed without an immediate presentation loop.
- Saved session and reachable, identity-verified server: continue into the library.
- Old DHCP address fails: broadcast Jellyfin discovery, match Server ID, verify the public system-info endpoint without a user token, and update the existing server record. Preserve accounts, configuration and all saved alternate URLs.
- Discovery fails: try saved alternatives concurrently, including optional Tailscale addresses. Each request has a four-second resource timeout. Failed startup goes to account/discovery UI, retaining credentials rather than making authenticated requests to an unverified address.
- Discovery page: local results first, visible bounded scan state, Search again, saved-server retry, optional manual input. No automatic keyboard. Eight-second scans stop on disappearance/background; foreground triggers another scan.
- Settings: optional alternate address field and explanation. Verify it identifies the existing server before saving. Adding it does not replace the current local URL; selecting a saved address also verifies identity.
- Bare IPv4/host/MagicDNS/bracketed IPv6 inputs default to HTTP and port 8096. Explicit URLs and ports preserve the user's scheme/default port choice. Credentials, query strings, fragments and ambiguous unbracketed IPv6 are rejected.

UI uses the existing discovery/list and TV split-screen patterns, with the shared server settings constrained to maximum rather than fixed width for phone/tablet use. Discovery failures explain checking local network access; implementation/entitlement terminology stays out of product copy.

Approach: reuse standard Jellyfin UDP discovery and existing Server ID keyed storage. Bonjour alone is not a replacement because standard Jellyfin servers do not guarantee that advertisement. Broad TCP subnet scanning is not introduced.

External release requirement: physical iOS/iPadOS UDP broadcast requires Apple's multicast entitlement approval and a provisioning profile containing it for org.chenacademy.watermelonfin. Current changes intentionally do not declare an unapproved capability that breaks signing. Hardware discovery remains unverified until that is enabled and tested. Source: https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy

Apple request rationale: WatermelonFin is a Jellyfin media client. It sends the standard discovery request on UDP 7359 only on the local network to let users find their own media server and recover a changed DHCP address. Responses are verified through public system information and matched by Server ID before reusing saved accounts. No unrelated service scanning is performed.
