# AFEN Open Platform — Integration Guide

**AFEN Vending Machines** · [www.AFENvend.com](https://www.AFENvend.com)

This folder contains **two separate integrations**. Implement both if your cloud serves admin dashboards **and** live vending machines.

---

## Integration overview

```
┌─────────────────────────────────────────────────────────────────┐
│  INTEGRATION #1 — Open Platform REST API                        │
│  Your backend / admin / kiosk app queries cloud                 │
│  Auth: app_id + sign + timestamp (JWT Bearer)                   │
│  Docs: Product · Device · Delivery Record · Non-cash flow       │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  INTEGRATION #2 — AFEN VMC Protocol V2.5                        │
│  Physical vending machine ↔ cloud (real-time)                   │
│  Auth: HTTP POST + JSON, FunCode field                          │
│  Doc: AFEN VMC Protocol V2.5.md                                 │
└─────────────────────────────────────────────────────────────────┘
```

| | **#1 Open Platform REST** | **#2 AFEN VMC V2.5** |
|---|---------------------------|----------------------|
| **Who calls** | Your server, kiosk app, admin panel | VMC firmware on the machine |
| **Format** | REST POST + signed query params | HTTP POST + JSON body with `FunCode` |
| **Purpose** | List products, devices, history | Live vend, load, poll, payment QR |
| **Poll interval** | On demand | FunCode 4000 every **3 seconds** |
| **Start reading** | Module files below | [AFEN VMC Protocol V2.5.md](./AFEN%20VMC%20Protocol%20V2.5.md) |

---

## Integration #1 — Open Platform REST API (module files)

| Module | Endpoint | Use case |
|--------|----------|----------|
| [Product module.md](./Product%20module.md) | `POST /api/product/getProductPage` | Product catalog, prices, images |
| [Device Module.md](./Device%20Module.md) | `POST /api/device/getDevicePage` | Machine list |
| [Device Module.md](./Device%20Module.md) | `POST /api/deviceSlot/getDeviceSlotList` | Slot inventory per machine |
| [Delivery Record Module.md](./Delivery%20Record%20Module.md) | `POST /api/shippingRecord/getShippingRecordPage` | Vend / shipment history |
| [Non-cash flow module.md](./Non-cash%20flow%20module.md) | `POST /api/nonCashFlow/getNonCashFlowPage` | WeChat / Alipay payment records |

**Common request params (all REST endpoints):**

| Param | Required | Description |
|-------|----------|-------------|
| app_id | yes | Application ID |
| method | yes | API method name |
| timestamp | yes | UTC `yyyy-MM-dd HH:mm:ss` |
| sign | yes | Request signature |
| sign_method | yes | `md5` or `hmac-sha256` |

---

## Integration #2 — AFEN VMC Protocol V2.5

**Full spec:** [AFEN VMC Protocol V2.5.md](./AFEN%20VMC%20Protocol%20V2.5.md)

| FunCode | Name | When |
|---------|------|------|
| **1000** | Load / delivery report | After vend or operator load |
| **2000** | Identify password | Customer enters 8-digit code / QR |
| **4000** | Return cycle poll | Every 3 s — remote vend, load, ads |
| **5000** | Delivery result feedback | After motor completes |
| **5001** | Load result feedback | After APP-initiated restock |
| **5002** | Ad download feedback | After FTP ad download |
| **8000** | Integral exchange | Generate payment QR |
| **9000** | Check pay result | Poll until payment confirmed |

### V2.5 terminologies

| Term | Description |
|------|-------------|
| **Loading password** | Operator opens machine doors. 8-digit numeric. Touch or QR. |
| **Pickup password** | Customer takes product. 8-digit numeric. Touch or QR. |

### V2.5 cloud rules

- All requests: **HTTP POST**
- All responses: **JSON**
- Server URL: **configured on VMC**

---

## How the two integrations work together

| Business action | REST API (#1) | VMC V2.5 (#2) |
|-----------------|---------------|---------------|
| Show product grid on kiosk | `getProductPage` or `getDeviceSlotList` | — |
| Customer buys with password | — | `2000` → vend → `5000` |
| Customer pays via QR/points | `getNonCashFlowPage` (history) | `8000` → `9000` → `2000` → `5000` |
| Remote APP triggers vend | — | `4000` MsgType=0 → `5000` |
| Operator restocks slot | — | `4000` MsgType=1 → `5001` → `1000` |
| Admin views vend history | `getShippingRecordPage` | — |
| Update ads on machine | — | `4000` MsgType=2 → `5002` |

---

## VMFS kiosk app mapping

| Kiosk feature | Which integration |
|---------------|-------------------|
| Product grid + prices | **#1** REST or vms-cloud `/machines/{no}/slots` |
| Add to cart / Buy | vms-cloud `POST /orders` (VMFS custom) |
| Physical motor vend | Local UART (`VendingMachineService`) — Reyeah board |
| Age verification QR | vms-cloud age-verification API |
| AFEN machine firmware | **#2** FunCode 2000 + 5000 instead of UART |

See also: `docs/AGE_VERIFICATION_API.md` in the kiosk repo root.

---

## File index

| File | Content |
|------|---------|
| **README.md** | This file — start here |
| **AFEN VMC Protocol V2.5.md** | Integration #2 — complete FunCode spec |
| **Product module.md** | Integration #1 — product REST API |
| **Device Module.md** | Integration #1 — device + slot REST API |
| **Delivery Record Module.md** | Integration #1 — shipment records REST API |
| **Non-cash flow module.md** | Integration #1 — payment records REST API |
| **2.0 Open Platform - Integration Guide.docx** | Original Word document |
