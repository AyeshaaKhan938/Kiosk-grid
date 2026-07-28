# AI Cooler (SMG-S400) — vms-cloud API

Headless kiosk flow for SenseMART SMG-S400 / BKX16 tablets. The customer pays on an external POS; the Flutter app polls vms-cloud, unlocks the cooler door, records dual cameras, uploads MP4s, then polls until billing completes.

Base URL: `https://cloud.vmfsusa.com/api/v1`

## Flow

```
POS payment success
  → vms-cloud creates order + pending cooler session
  → kiosk GET /machines/{machine_no}/cooler-sessions/pending
  → kiosk POST /cooler-sessions/ack
  → kiosk unlocks door + records (native BKX SDK)
  → customer closes door
  → kiosk POST /cooler-sessions (multipart host_video + sub_video)
  → AI or operator identifies SKUs + qty
  → vms-cloud captures final amount + decrements stock
  → kiosk GET /orders/{order_id} until status = completed | failed
```

## Endpoints

### 1. Pending session (kiosk poll)

```
GET /machines/{machine_no}/cooler-sessions/pending
```

**200 OK** — session ready:

```json
{
  "order_id": "ord_abc123",
  "session_id": "sess_xyz789",
  "payment_verified": true,
  "amount_authorized": 50.0
}
```

**204 No Content** or **404** — nothing pending (kiosk keeps polling every ~3 s).

Only return a session once `payment_verified` is true (POS webhook confirmed).

### 1b. Create session from POS (protected)

Called by vms-cloud when the external POS confirms payment (or manually from admin tools).

```
POST /api/v1/admin/cooler-sessions/pos-payment
Authorization: Bearer {LOTTERY_MANAGEMENT_API_TOKEN}
Content-Type: application/json
```

```json
{
  "machine_no": "866903255700003",
  "amount_authorized": 50.0,
  "payment_reference": "auth_code_from_pos",
  "payment_verified": true
}
```

**201 Created** — same shape as pending poll response.


```
POST /cooler-sessions/ack
Content-Type: application/json
```

```json
{
  "machine_no": "866903255700003",
  "order_id": "ord_abc123",
  "session_id": "sess_xyz789"
}
```

Marks the session as `claimed` so other polls do not re-deliver it.

### 3. Upload videos

```
POST /cooler-sessions
Content-Type: multipart/form-data
```

| Field        | Type   | Required |
|-------------|--------|----------|
| machine_no  | string | yes      |
| order_id    | string | yes      |
| session_id  | string | yes      |
| host_video  | file   | yes      |
| sub_video   | file   | yes      |

Store videos, set order status to `pending_review` or `processing`, enqueue AI review job.

**200/201** on success.

### 4. Report failure

```
POST /cooler-sessions/failed
Content-Type: application/json
```

```json
{
  "machine_no": "866903255700003",
  "order_id": "ord_abc123",
  "session_id": "sess_xyz789",
  "error": "Door timeout — customer did not close door"
}
```

Release POS authorization / notify operator as appropriate.

### 5. Order status (kiosk poll)

```
GET /orders/{order_id}
```

```json
{
  "order_id": "ord_abc123",
  "status": "processing",
  "message": "Reviewing video",
  "final_amount": null
}
```

Terminal statuses: `completed`, `failed`, `cancelled`.

On `completed`, include `final_amount` (actual charge after item identification).

## Order status values

| Status           | Meaning                                      |
|-----------------|----------------------------------------------|
| paid            | POS authorized; pending kiosk pickup         |
| claimed         | Kiosk acknowledged; door session starting    |
| recording       | Door open / cameras rolling                  |
| pending_review  | Videos uploaded; awaiting AI or operator     |
| processing      | Billing / stock update in progress           |
| completed       | Final charge captured; stock decremented     |
| failed          | Session or review failed                     |

## Laravel implementation notes

- Create pending session when POS webhook hits (same machine_no as kiosk config).
- `amount_authorized` is the hold/max charge from POS; `final_amount` is post-review capture.
- Decrement `machine_slots` per identified SKU (same tables as slot vending).
- Admin UI for abnormal orders (empty take, disputed items) before capture.

## Kiosk configuration

Admin → **Dispense hardware** → **AI cooler (SMG-S400 / BKX16)**.

When `hardwareProtocol == bket`, the app boots to `CoolerShadowScreen` (no product grid / cart / checkout).
