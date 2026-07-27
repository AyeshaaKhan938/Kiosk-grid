# Kiosk Machine-Wise Updates API — vms-cloud Backend Spec

The Flutter kiosk app polls for APK updates **per machine**. Different clients and different machines under the same client can run different approved app versions.

## Kiosk behaviour (already implemented)

Every ~30 seconds (plus jitter), each kiosk calls:

```
GET /api/v1/kiosk/update-check?current_version_code={buildNumber}&machine_no={machineNo}
Accept: application/json
```

| Query param | Required | Example | Purpose |
|-------------|----------|---------|---------|
| `current_version_code` | yes | `39` | Installed APK `versionCode` from `pubspec.yaml` (`1.4.22+39` → `39`) |
| `machine_no` | yes* | `866903255700003` | Serial / machine number configured in the setup wizard |

\*If `machine_no` is empty (misconfigured kiosk), the kiosk omits the param and the backend should fall back to the global default release.

## Resolution order (recommended)

When vms-cloud receives an update check:

1. Look up **machine-specific assignment** for `machine_no` (pinned version or explicit “offer this APK”).
2. If none, look up **client / operator group** assignment (all machines owned by the same client).
3. If none, fall back to the **global default** kiosk release (current behaviour).

Return `update_available: false` when the machine’s assigned `version_code` is less than or equal to `current_version_code`.

Return `update_available: false` when the machine is **blocked** from updating (e.g. quarantined on a known-good build).

## Response — no update

```json
{
  "update_available": false
}
```

## Response — update offered

```json
{
  "update_available": true,
  "version_code": 40,
  "version_name": "1.4.23",
  "apk_url": "/storage/kiosk-updates/vmfs-kiosk-1.4.23.apk",
  "apk_sha256": "abc123…",
  "apk_size_bytes": 59200000,
  "mandatory": false,
  "release_notes": "AFEN coil fix for machine 866903255700003",
  "machine_no": "866903255700003",
  "assignment_type": "machine"
}
```

| Field | Type | Notes |
|-------|------|-------|
| `update_available` | bool | `true` when a newer assigned build exists |
| `version_code` | int | Must be **greater than** `current_version_code` |
| `version_name` | string | Display string, e.g. `1.4.23` |
| `apk_url` | string | Absolute URL or `/storage/…` path (kiosk resolves both) |
| `apk_sha256` | string? | Optional integrity check |
| `apk_size_bytes` | int? | Optional, used for progress UI |
| `mandatory` | bool | When `true`, kiosk should treat as required (future UI) |
| `release_notes` | string? | Shown in admin “Check for Updates” |
| `machine_no` | string? | Echo / audit — which assignment matched |
| `assignment_type` | string? | `machine`, `client`, or `global` |

## vms-cloud admin — suggested data model

### `kiosk_releases`

Stores uploaded APK metadata (one row per build):

- `version_code`, `version_name`, `apk_path`, `sha256`, `size_bytes`, `release_notes`, `is_active`

### `kiosk_machine_updates`

Per-machine override:

| Column | Example | Notes |
|--------|---------|-------|
| `machine_id` | FK → machines | Required |
| `kiosk_release_id` | FK → kiosk_releases | APK offered to this machine |
| `pin_version` | bool | When true, never offer newer global builds |
| `blocked` | bool | When true, never offer any update |
| `notes` | text | Operator notes |

### `kiosk_client_updates` (optional)

Same as above but keyed by `client_id` / operator account — applies to all machines unless a machine row overrides it.

## Admin UI (cloud)

Suggested screens under **Settings → Kiosk Updates**:

1. **Releases** — upload APK, set version code/name, activate/deactivate.
2. **Machine assignments** — search machine by serial, pick release, pin/block.
3. **Bulk assign** — select client → assign release to all their machines.

## Backward compatibility

Older kiosks that do not send `machine_no` continue to work if the backend keeps the existing global update logic when the parameter is missing.

New kiosks (this repo) always send `machine_no` after setup.

## Testing

```bash
curl -s "https://cloud.vmfsusa.com/api/v1/kiosk/update-check?current_version_code=39&machine_no=866903255700003"
```

Machine A on build 39 should receive APK X; machine B on build 39 should receive APK Y (or no update) according to cloud assignments.
