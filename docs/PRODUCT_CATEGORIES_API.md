# Product Categories API — vms-cloud Backend Spec

The kiosk product browser supports **shop-by-category**, sorting, and filtering. Categories can come from the slots response or be managed centrally in vms-cloud.

## Kiosk behaviour (implemented)

1. `GET /api/v1/machines/{machine_no}/slots` may include a `categories` array (see below).
2. If omitted, the kiosk derives categories from each slot’s `product_category` string.
3. Customers filter via category chips and a category menu; operators manage categories in vms-cloud admin.

## Slots response — add categories block

Extend the existing slots endpoint:

```json
{
  "machine_number": "866903255700003",
  "machine_name": "Production Kiosk",
  "categories": [
    {
      "id": 1,
      "name": "Beverages",
      "slug": "beverages",
      "icon_url": "https://cloud.vmfsusa.com/storage/categories/bev.png",
      "sort_order": 10
    },
    {
      "id": 2,
      "name": "Snacks",
      "slug": "snacks",
      "sort_order": 20
    }
  ],
  "slots": [
    {
      "line_number": 1,
      "product_name": "Coca-Cola",
      "product_category": "Beverages",
      "price": 2.50,
      "current_stock": 5,
      "max_stock": 10,
      "is_available": true,
      "is_fault": false
    }
  ]
}
```

| Field | Type | Notes |
|-------|------|-------|
| `categories[].id` | int | Stable ID for admin |
| `categories[].name` | string | Display label on kiosk chips |
| `categories[].slug` | string? | URL-safe key |
| `categories[].icon_url` | string? | Optional chip icon (future) |
| `categories[].sort_order` | int | Chip order left → right |
| `slots[].product_category` | string? | Must match a category `name` (or free text until admin syncs) |

## Recommended vms-cloud admin

### `product_categories` table

| Column | Notes |
|--------|-------|
| `id` | PK |
| `client_id` | FK — optional multi-tenant |
| `name` | e.g. Beverages |
| `slug` | beverages |
| `icon_path` | optional |
| `sort_order` | int |
| `is_active` | bool |

### `products.category_id` (or slot assignment)

Link each product (or machine slot line) to one category. When slots are built for the API, emit `product_category` = category name.

### Admin UI

**Products → Categories**

- CRUD categories (name, sort order, active)
- Drag to reorder
- Assign products to categories in product edit form
- Preview: “How kiosk chips will appear”

### Machine-specific overrides (optional)

`machine_slot_categories` — override category for a product on one machine only.

## Advertisement slot `top`

Placeholder ads titled `"test"` or without `media_url` are **ignored** on the product browser banner so operators see demo/promo content until a real image ad is configured.

## Testing

```bash
curl -s "https://cloud.vmfsusa.com/api/v1/machines/866903255700003/slots" | jq '.categories'
```

Ensure at least one slot has `product_category` matching a category name for filter chips to show meaningful groups.
