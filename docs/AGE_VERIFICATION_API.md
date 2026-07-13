# Age Verification API — vms-cloud Backend Spec

This document describes the API endpoints the **vms-cloud** Laravel backend must implement to support the kiosk age-verification flow. The Flutter kiosk app and mobile upload page (`web/verify/index.html`) are already wired to these routes.

## Flow Overview

```
Customer taps kiosk
       │
       ▼
Kiosk POST /age-verification/sessions  ──► session_id + verify_url
       │
       ▼
Kiosk displays QR ──► Customer scans with phone
       │
       ▼
Phone opens https://cloud.vmfsusa.com/verify?session={id}
       │
       ▼
Customer uploads ID photo ──► POST /age-verification/sessions/{id}/document
       │
       ▼
Backend forwards image to third-party verifier (Jumio, Veriff, Onfido, etc.)
       │
       ▼
Kiosk polls GET /age-verification/sessions/{id} until status = verified
       │
       ▼
Customer enters redemption code ──► POST /scratch-card/redeem (with session_id)
```

## Endpoints

### 1. Create Session

```
POST /api/v1/age-verification/sessions
Content-Type: application/json

{
  "machine_no": "866903255700003"
}
```

**Response `201 Created`:**

```json
{
  "session_id": "550e8400-e29b-41d4-a716-446655440000",
  "verify_url": "https://cloud.vmfsusa.com/verify?session=550e8400-e29b-41d4-a716-446655440000",
  "expires_at": "2025-06-26T15:30:00Z"
}
```

- Sessions should expire after **10–15 minutes**.
- One session per kiosk visit; do not reuse across customers.

---

### 2. Upload ID Document (mobile web)

```
POST /api/v1/age-verification/sessions/{session_id}/document
Content-Type: multipart/form-data

document       = (image file, max 10 MB, JPEG/PNG)
document_type  = drivers_license | id_card | passport
```

**Response `200 OK`:**

```json
{
  "status": "processing",
  "message": "Document received. Verification in progress."
}
```

**Backend responsibilities:**

1. Validate session exists and is not expired.
2. Store image temporarily (encrypted, auto-delete after verification).
3. Send image to third-party age/ID verification service.
4. Update session status as the provider returns results.

---

### 3. Poll Session Status

```
GET /api/v1/age-verification/sessions/{session_id}
```

**Response `200 OK`:**

```json
{
  "session_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "verified",
  "age_verified": true,
  "message": null
}
```

**Status values:**

| Status       | Meaning                                      |
|--------------|----------------------------------------------|
| `pending`    | Session created, no document uploaded yet    |
| `uploaded`   | Document received, not yet sent to provider    |
| `processing` | Third-party verification in progress           |
| `verified`   | Age confirmed 18+ (`age_verified: true`)     |
| `rejected`   | Under 18, invalid document, or fraud         |
| `expired`    | Session timed out                              |

---

### 4. Scratch-Card Redeem (existing — add field)

```
POST /api/v1/scratch-card/redeem
Content-Type: application/json

{
  "code": "ABC123",
  "machine_no": "866903255700003",
  "age_verification_session_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

When age verification is enabled for a machine, **reject redemption** (`422`) if:

- `age_verification_session_id` is missing
- Session status is not `verified` with `age_verified: true`
- Session belongs to a different machine
- Session is older than 30 minutes

```json
{
  "message": "Age verification required. Please scan the QR code on the kiosk."
}
```

---

## Mobile Web Page Deployment

Deploy `web/verify/index.html` to the Laravel public directory:

```
public/verify/index.html
```

Or configure a route that serves the same page. The page reads `?session=` from the URL and posts to the API on the same origin.

---

## Third-Party Verification Providers

Recommended integrations (backend choice):

| Provider | Use case                    | Docs |
|----------|-----------------------------|------|
| **Veriff** | ID + age verification     | https://developers.veriff.com |
| **Jumio**  | Document verification     | https://docs.jumio.com |
| **Onfido** | Government ID checks      | https://documentation.onfido.com |
| **ID.me**  | US government ID + age    | https://developers.id.me |

### Minimum verification checks

- Document is a valid government-issued ID or passport
- Date of birth indicates age **≥ 18**
- Document is not expired (optional but recommended)
- Liveness / anti-fraud score above provider threshold

### Data retention

- Delete ID images within **24 hours** after verification completes
- Store only: `session_id`, `machine_no`, `status`, `verified_at`, provider reference ID
- Do **not** store full document images long-term

---

## Kiosk Admin Toggle

Operators enable/disable age verification per kiosk via **Admin Panel → Age Verification (18+)**. When OFF, the kiosk skips the QR screen and goes directly to code entry (current behavior).

---

## Environment Variables (kiosk `.env`)

```
AGE_VERIFICATION_WEB_BASE=https://cloud.vmfsusa.com
```

Laravel `.env` (backend):

```
AGE_VERIFICATION_PROVIDER=veriff   # or jumio, onfido
VERIFF_API_KEY=...
VERIFF_API_SECRET=...
AGE_VERIFICATION_MIN_AGE=18
```
