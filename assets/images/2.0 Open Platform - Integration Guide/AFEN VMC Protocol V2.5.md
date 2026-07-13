# AFEN VMC Protocol — Interface Design V2.5

**AFEN Vending Machines R&D Center**  
[www.AFENvend.com](https://www.AFENvend.com)

[← Back to Integration Guide](./README.md)

> This is **Integration #2**. For cloud REST APIs (products, devices, records), see the four module files listed in [README.md](./README.md).

---

## 1. Preface

### 1.1 Purposes

This document describes the **VMC ↔ Cloud** protocol:

- Flowchart and organization
- Modules, functions, interface design, data structures

**Note:** QR code flows require additional hardware (camera) or a customer phone. The touch screen alone cannot scan QR without extra devices.

### 1.2 Terminologies

| Term | Description |
|------|-------------|
| **Loading the machine** | Operator verification to open doors. Touch screen or QR scan. **8-digit numeric password.** |
| **Passwords to take products away** | Customer pickup codes. Touch screen or QR scan. **8-digit numeric password.** |

---

## 2. Cloud system design

| Rule | Value |
|------|-------|
| Request method | **HTTP POST** |
| Response format | **JSON** |
| Server URL | **Configurable on VMC** |

---

## 2.1 FunCode index

| FunCode | Section | Purpose |
|---------|---------|---------|
| 1000 | [§2.1.1](#211-loaddelivery-funcode-1000) | Load / delivery report |
| 2000 | [§2.1.2](#212-identify-password-funcode-2000) | Identify password → authorize vend |
| 4000 | [§2.1.3](#213-return-cycle-funcode-4000) | Poll server commands (every **3 s**) |
| 5000 | [§2.1.4.1](#2141-delivery-result-feedback-funcode-5000) | Delivery result feedback |
| 5001 | [§2.1.4.3](#2143-app-load-result-feedback-funcode-5001) | APP load result feedback |
| 5002 | [§2.1.4.5](#2145-ad-download-result-funcode-5002) | Ad download result feedback |
| 8000 | [§2.1.5](#215-integral-exchange-funcode-8000) | Integral exchange → payment QR |
| 9000 | [§2.1.6](#216-check-integral-exchange-pay-result-funcode-9000) | Check payment result |

---

## 2.1.1 Load/Delivery (FunCode 1000)

VMC reports load or delivery event to cloud.

### Request

| Field | Type | Description |
|-------|------|-------------|
| FunCode | String | `1000` |
| MachineID | String | Machine ID |
| TradeNo | String | Trade no — return as original |
| SlotNo | String | Slot number |
| KeyNum | Int | Key number (keyboard machines) |
| Status | Int | `0` = OK, other = fail |
| Quantity | Int | Load / delivery quantity |
| Stock | Int | Stock after load/delivery |
| Capacity | String | Slot capacity |
| ProductID | String | Product ID |
| Price | String | Unit price (e.g. `1.5`) |
| Type | String | Product type |
| Introduction | String | Product introduction |
| Name | String | Product name |

### Response

```json
{
  "Status": "0",
  "SlotNo": "22",
  "TradeNo": "20170802193446876",
  "Err": "success",
  "ImageUrl": "http://xxx.com/201708029502889.png",
  "ImageDetailUrl": "http://xxx.com/20170801124323318.png"
}
```

| Field | Description |
|-------|-------------|
| Status | `0` = success · `1` = upload again · other = fail |
| SlotNo | Required |
| TradeNo | Return as original |
| ImageUrl | Product image URL |
| ImageDetailUrl | Product detail image URL |
| Err | Error description |

---

## 2.1.2 Identify password (FunCode 2000)

Customer enters password on screen or scans QR. Cloud returns slot/product to vend.

### Request

| Field | Type | Description |
|-------|------|-------------|
| FunCode | String | `2000` |
| TradeNo | String | Return as original |
| SessionCode | String | Delivery password (touch/QR). **Cannot use with Account/PWD.** |
| MachineID | String | Machine ID |
| SlotNo | String | Slot number |
| Price | String | Unit price |
| Account | String | Alternative auth (choose Account **or** SessionCode) |
| PWD | String | Alternative auth password |

### Response

```json
{
  "Status": "0",
  "SlotNo": "23",
  "ProductID": "1002356",
  "TradeNo": "20170609123523569",
  "Err": "Suc"
}
```

| Field | Description |
|-------|-------------|
| Status | `0` = success, other = fail |
| SlotNo | Slot(s) to vend. Multiple: `23\|28` |
| ProductID | If SlotNo > 0 → vend by slot. If vend by ProductID → SlotNo must be `< 1` |
| TradeNo | Required — return as original |
| Err | Error description |

---

## 2.1.3 Return cycle (FunCode 4000)

**VMC polls cloud every 3 seconds.** Used for APP remote vend, loading, and ads.

### Request

| Field | Type | Description |
|-------|------|-------------|
| FunCode | String | `4000` |
| MachineID | String | Machine ID |

### Response — MsgType 0 (server controls delivery)

```json
{
  "Status": "0",
  "MsgType": "0",
  "TradeNo": "20170609123523569",
  "SlotNo": "25",
  "ProductID": "1005678692",
  "Err": "SUC"
}
```

| Field | Description |
|-------|-------------|
| Status | `0` = success, other = fail |
| MsgType | `0` = delivery command |
| SlotNo | Slot to vend |
| ProductID | Product ID (slot-based vs product-based rules same as 2000) |

### Response — MsgType 1 (APP loading / restock)

```json
{
  "Status": "0",
  "MsgType": "1",
  "SlotNo": "25",
  "TradeNo": "111111",
  "Capacity": "1",
  "Quantity": "1",
  "ProductID": "111111",
  "Name": "dsff",
  "Price": "2.0",
  "Type": "yinl",
  "Introduction": "ssfsf",
  "ImageUrl": "http://xxx.com/201708029502889.png",
  "ImageDetailUrl": "http://xxx.com/201708029502889.png",
  "GoodsAdUrl": "ssfsf",
  "Err": "Suc"
}
```

| Field | Description |
|-------|-------------|
| Status | `0` = need load, other = no load needed |
| MsgType | `1` = load command |

> After load succeeds → send **FunCode 5001**. Allow time for VMC to update slot data before confirming.

### Response — MsgType 2 (remote advertising)

```json
{
  "MsgType": "2",
  "AdInfo": [
    {
      "Status": "0",
      "MachingID": "1234567890",
      "Ftp": "host|user|password",
      "PlayTime": "08:30~17:30|19:30~21:30",
      "AdFiles": "s123.png|m98.jpg",
      "AdType": "1"
    }
  ]
}
```

| Field | Description |
|-------|-------------|
| MsgType | `2` = advertising |
| Status | `0` = need download, other = skip |
| Ftp | Format: `host\|user\|password` |
| PlayTime | Multiple times separated by `\|` |
| AdFiles | Multiple files separated by `\|` |
| AdType | `0` = normal · `1` = standby · `2` = background · `3` = help · `4` = word ad |

> Return **all** released ads (including already downloaded). Local VMC deletes ads not in response. After download → **FunCode 5002**.

---

## 2.1.4 Result feedback

### 2.1.4.1 Delivery result feedback (FunCode 5000)

| Field | Type | Description |
|-------|------|-------------|
| FunCode | String | `5000` |
| MachineID | String | Machine ID |
| PayType | Int | Payment type |
| TradeNo | String | Trade number |
| SlotNo | String | Slot number |
| Status | Int | `0` = success · `1` = fail · `2` = success, bad trade no · `3` = fail, bad trade no · `4` = unknown |
| Time | String | Delivery time |
| Amount | String | Amount |
| ProductID | String | Product ID |
| Name | String | Product name |
| Type | String | Product type |

**Response:** `{"Status":"0","TradeNo":"...","SlotNo":"25","Err":"Suc"}`

### 2.1.4.3 APP load result feedback (FunCode 5001)

| Field | Type | Description |
|-------|------|-------------|
| FunCode | String | `5001` |
| MachineID | String | Machine ID |
| SlotNo | String | Slot number |
| Status | Int | `0` = success, other = fail |

**Response:** `{"Status":"0","SlotNo":"25","TradeNo":"...","Err":"suc"}`

### 2.1.4.5 Ad download result (FunCode 5002)

| Field | Type | Description |
|-------|------|-------------|
| FunCode | String | `5002` |
| MachineID | String | Machine ID |
| FileName | String | Ad file name |
| Status | Int | `0` = success · `1` = type mismatch · `2` = fail |

**Response:** `{"Status":"0","MachineID":"...","AdFiles":"d123.png","Err":"suc"}`

---

## 2.1.5 Integral exchange (FunCode 8000)

Generate payment QR for points/cashless exchange.

### Request

| Field | Type | Description |
|-------|------|-------------|
| FunCode | String | `8000` |
| MachineID | String | Machine ID |
| TradeNo | String | Trade number |
| SlotNo | String | Slot number |
| Price | String | Unit price |
| NotifyUrl | String | Pay-result callback URL |

### Response

```json
{
  "Status": "0",
  "Err": "suc",
  "CodeUrl": "123456789",
  "TradeNo": "20170609123523569"
}
```

| Field | Description |
|-------|-------------|
| CodeUrl | QR code content from server |
| TradeNo | Trade number |

---

## 2.1.6 Check integral exchange pay result (FunCode 9000)

### Request

| Field | Type | Description |
|-------|------|-------------|
| FunCode | String | `9000` |
| MachineID | String | Machine ID |
| TradeNo | String | Trade number |

### Response

```json
{
  "Status": "0",
  "Err": "suc",
  "MachineID": "123456789",
  "TradeNo": "20170609123523569"
}
```

| Status | Meaning |
|--------|---------|
| `0` | Payment successful |
| other | Not paid / failed |

---

## End-to-end flows

### Cashless vend (integral exchange)

```
8000 → display CodeUrl QR → customer pays → poll 9000 until Status=0
  → 2000 (password/session) OR 4000 MsgType=0 → motor vend → 5000 feedback
```

### Password / QR pickup

```
Customer enters SessionCode (2000) → SlotNo + ProductID → vend → 5000
```

### Remote APP vend

```
VMC polls 4000 every 3s → MsgType=0 received → vend → 5000
```

### Operator restock

```
4000 MsgType=1 → VMC loads slot → wait → 5001 feedback → 1000 load report
```

---

## Relation to Open Platform REST API

| V2.5 FunCode | Open Platform equivalent (approx.) |
|--------------|-------------------------------------|
| 1000 Load report | Updates slot inventory → `getDeviceSlotList` |
| 2000 Password vend | Creates shipping record → `getShippingRecordPage` |
| 4000 Poll | Real-time command channel (no REST equivalent) |
| 5000 Delivery feedback | `shippingRecords.status` field |
| 8000/9000 Payment | `getNonCashFlowPage` records |
| Product fields in 1000/4000 | `getProductPage` catalog |

Both integrations can run on the same cloud backend — REST for admin/reporting, FunCode for live VMC communication.
