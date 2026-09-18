# Kiosk payment → vend

## Customer flow

1. **Buy Now** / cart **Buy** opens `PaymentScreen` (not vend yet).
2. Customer chooses **Card** or **Cash** (admin can disable either).
3. **Card** — waits for Contaloupe / Nayax success (or Simulate Payment).
4. **Cash** — waits until bill/coin credit ≥ amount (simulate buttons in lab).
5. Only after success → `POST /api/v1/orders` with `payment_reference` → dispense.

## Admin (kiosk)

- **Customer payment** section:
  - Card / Cash toggles
  - Simulate payment (demo without hardware)
  - Card reader: Simulate | Nayax | Contaloupe

## Native bridge (Android)

Channel: `vmfs.kiosk/payment` + events `vmfs.kiosk/payment_events`

Broadcasts (OEM / field wiring):

- `com.vmfsusa.kiosk.PAYMENT_RESULT` — extras: `type` (`success`|`declined`|`error`), `reference`, `provider`, `amount_cents`
- `com.vmfsusa.kiosk.CASH_CREDIT` — extras: `amount_cents`

Plug Nayax / Contaloupe SDKs into `PaymentChannel.kt` (or send the broadcasts above).

## Cloud

`POST /api/v1/orders` requires `payment_reference`. Orders without it are rejected (422).
