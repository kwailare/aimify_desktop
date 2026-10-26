# Aimify Desktop API — reference

For the Aimify desktop client (Flutter) to authenticate against and read data
from the `aimify-web` backend. Copy this file into the desktop project so a
fresh session there has the contract without needing this conversation's
history.

## How auth works

The web dashboard authenticates via a browser session cookie (NextAuth). A
native desktop client has no browser to hold that cookie, so it uses a
separate, token-based path instead:

1. `POST /api/v1/auth/login` with an email + password → get back a signed JWT.
2. Send that JWT as `Authorization: Bearer <token>` on every subsequent
   request.
3. Each login creates a server-side session (device name, IP, last activity)
   and the token is a signed JWT (HS256, 30-day expiry) tied to it. The token
   stops working, at once, when the session is revoked. Sessions are revoked
   by `POST /auth/logout`, by the user from Settings on the website ("Sign
   out" on a device, or "Sign out other devices"), and automatically for every
   device when the person changes or resets their password, an admin resets it,
   or they are removed from the team. A revoked or expired token gets `401`, so
   the desktop client should treat `401` as "sign in again".

The user must already have an Aimify account (created via the web app's
`/signup`) before they can log in from the desktop client — this API does not
currently expose account creation.

## Subscription gating

The subscription is what unlocks the desktop app, so every endpoint below
`/me` checks the organization's `subscriptionStatus` before doing anything.
Only `trial`, `active` and `past_due` get through. The rest are rejected:

| `subscriptionStatus` | Response |
|---|---|
| `pending`, `expired`, `cancelled` | `402` |
| `suspended` | `403` |

```json
{
  "error": "Your free trial has ended. Subscribe on the Aimify website to keep using the desktop app.",
  "code": "subscription_inactive",
  "subscriptionStatus": "expired"
}
```

The desktop client should branch on `code === "subscription_inactive"` and
show `error` to the user with a link to the website's billing page, rather
than treating it as a generic failure. `POST /auth/login` and `GET /me` are
**not** gated, so a locked-out user can still sign in and the client can read
their status from `/me`.

Trials end automatically: the first request after `trialEndsAt` passes flips
the status from `trial` to `expired`, so `/me` always reports the real value.

## Roles and permissions

Each person has a role, set on the website's Team page and returned by `/me`.
What each role may do is a per-organization grid the Owner edits on the
website (Team, then Roles & permissions). Every organization starts with the
defaults below. Owners always hold every permission and their row can't be
changed. Every endpoint, reads included, checks the grid after the
subscription check. A refused call gets `403`:

```json
{
  "error": "Your role (Sales Staff) isn't allowed to do this.",
  "code": "forbidden_role",
  "role": "Sales Staff",
  "permission": "products.create"
}
```

`/me` returns `permissions`, everything the signed-in person currently holds,
so the desktop app can hide screens and controls instead of waiting for a
`403`. An Owner's change applies on the very next request; the app picks it
up whenever it re-reads `/me` (after any `402`/`403`, and on refresh).

| Module | Permission | Covers | Default roles |
|---|---|---|---|
| Products | `products.view` | List and read products | Everyone |
| | `products.create` | Add a product | Owner, Administrator, Warehouse Manager, Inventory Staff |
| | `products.edit` | Edit a product, upload or remove its image | Owner, Administrator, Warehouse Manager, Inventory Staff |
| | `products.archive` | Archive or restore a product | Owner, Administrator, Warehouse Manager |
| Categories & units | `catalog.view` | List categories and units | Everyone |
| | `catalog.create` | Add a category or unit | Owner, Administrator, Warehouse Manager, Inventory Staff |
| | `catalog.delete` | Delete a category or unit | Owner, Administrator, Warehouse Manager, Inventory Staff |
| Stock movements | `stock.view` | List movements and stock alerts | Everyone |
| | `stock.in` | Record `stock_in` | Owner, Administrator, Warehouse Manager, Inventory Staff |
| | `stock.out` | Record `stock_out` | The roles above plus Sales Staff |
| | `stock.adjust` | Record `adjustment` and `count` | Owner, Administrator, Warehouse Manager, Inventory Staff |
| Warehouses | `warehouses.view` | List warehouses | Everyone |
| | `warehouses.create` | Add a warehouse | Owner, Administrator, Warehouse Manager |
| | `warehouses.edit` | Edit a warehouse's details | Owner, Administrator, Warehouse Manager |
| | `warehouses.disable` | Disable or re-enable a warehouse | Owner, Administrator, Warehouse Manager |
| Customers | `customers.view` | List and read customers and their credit ledger | Owner, Administrator, Sales Staff, Accountant / Finance |
| | `customers.create` / `.edit` / `.archive` | Add, edit, archive or restore | Owner, Administrator, Sales Staff |
| | `customers.types` | Add, rename and remove customer types and their default credit limits | Owner, Administrator |
| Suppliers | `suppliers.view` | List and read suppliers and their credit ledger | Owner, Administrator, Warehouse Manager, Accountant / Finance |
| | `suppliers.create` / `.edit` / `.archive` | Add, edit, archive or restore | Owner, Administrator, Warehouse Manager |
| Credit ledger | `credit.record` | Record charges, payments and adjustments (also needs view of that customer or supplier) | Owner, Administrator, Accountant / Finance |
| Purchases | `purchases.view` | List and read purchases | Owner, Administrator, Warehouse Manager, Accountant / Finance |
| | `purchases.create` | Record a purchase and edit it while nothing is received | Owner, Administrator, Warehouse Manager |
| | `purchases.receive` | Receive deliveries (adds stock) | Owner, Administrator, Warehouse Manager |
| | `purchases.cancel` | Cancel a purchase nothing was received on | Owner, Administrator, Warehouse Manager |
| Sales | `sales.view` | List and read sales | Owner, Administrator, Sales Staff, Accountant / Finance |
| | `sales.create` | Record a sale (and take payment at the counter) | Owner, Administrator, Sales Staff |
| | `sales.discount` | Sell at a price other than the product's, or give a discount | Owner, Administrator |
| | `sales.override` | Complete a credit sale over the customer's credit limit | Owner, Administrator |
| | `sales.void` | Void a sale (stock goes back) | Owner, Administrator |
| Fixed | `team.manage` | List the team and invite people | Owner, Administrator (not editable) |
| | `setup.complete` | Mark the guided setup as finished | Owner, Administrator (not editable) |

Some permissions bring others with them, because the action can't work
without them: every action includes its module's `view`; `stock.in`,
`stock.out` and `stock.adjust` include `products.view` and `warehouses.view`
(a movement picks both); `products.create` and `products.edit` include
`catalog.view`; `purchases.create` and `purchases.receive` include
`products.view` and `warehouses.view`; `sales.create` includes `products.view` and
`warehouses.view`, and `sales.discount` and `sales.override` include `sales.create`. The grid editor applies the same rule, so a saved grid is
always consistent.

An update that changes `status` (archive, restore, disable, re-enable) needs
the archive/disable permission; an update that changes other fields needs the
edit permission; one that does both needs both, and is refused as a whole if
either is missing.

For desktop builds released before this grid existed, `/me` also still sends
the older combined keys, derived from the grid: `products.write`,
`catalog.write`, `warehouses.manage`, `customers.read`, `customers.write`,
`suppliers.read` and `suppliers.write`. New code should use the keys above.
The rules live in `lib/permissions.ts` in `aimify-web`.

## Plan limits

Each organization is on a plan (set by the Aimify team in the admin panel)
that can cap team members, active warehouses and active products. A cap left
empty means unlimited. When a write would go over a cap, the API returns `403`:

```json
{
  "error": "Your Full Access plan allows 1 active warehouse. Disable one before adding another.",
  "code": "plan_limit",
  "limit": 1,
  "used": 1
}
```

Enforced on: creating a warehouse, re-activating a disabled one, creating a
product, and re-activating an archived one. Archiving a product or disabling a
warehouse frees a slot. Team-member limits apply on the website when inviting
and accepting invitations. `GET /me` returns the plan so the desktop app can
show usage before hitting a limit:

```json
"plan": {
  "name": "Full Access",
  "limits": { "users": null, "warehouses": 1, "products": null },
  "usage": { "users": 2, "warehouses": 1, "products": 34 }
}
```

`null` in `limits` means unlimited. The role check (`forbidden_role`) runs
before the limit check.

## Payments and subscription status

`organization.currentPeriodEnd` is set once the organization has paid at
least once (via Paystack on the website); it is the date the current paid
period ends. `cancelAtPeriodEnd` is `true` when the owner has cancelled but
the paid period hasn't ended yet — access and `subscriptionStatus` stay
normal until then. `subscriptionStatus` can be `past_due` for a few days
after a renewal fails (the app still works) before it becomes `expired`.
There is no payment endpoint in this API: all payment is done on the website
(`/dashboard/billing`), which is where a locked screen's "manage billing"
link should send people.

## Base URL

| Environment | URL |
|---|---|
| Local dev | `http://localhost:3000` |
| Production | *(fill in once deployed — your Vercel domain)* |

## `POST /api/v1/auth/login`

Request:

```json
{
  "email": "you@company.com",
  "password": "your-password",
  "deviceName": "Shop counter PC"
}
```

`deviceName` is optional (up to 80 characters). It labels this sign-in in the
user's "Signed-in devices" list on the website; without it the label falls
back to the request's `User-Agent`.

Success — `200`:

```json
{
  "token": "eyJhbGciOiJIUzI1NiJ9....",
  "expiresAt": "2026-10-26T09:00:00.000Z"
}
```

If the person has turned on two-factor authentication, also send the current
6-digit code from their authenticator app, or one of their backup codes, as
`code`:

```json
{
  "email": "you@company.com",
  "password": "your-password",
  "code": "123456"
}
```

Without it, a correct password gets `401` with `"code": "two_factor_required"`
and no token, so the client should show a code prompt and send the same request
again with `code`. A wrong or already-used code gets `401` with
`"code": "invalid_two_factor_code"`. Authenticator codes work once, and a backup
code works once. Wrong codes count toward the same rate limit as wrong
passwords.

Failure — `400` (missing fields) or `401` (wrong email/password):

```json
{
  "error": "Invalid email or password."
}
```

Failure — `429` (rate limited): after 5 failed attempts within 15 minutes
from the same IP, or 5 failed attempts against the same email, further
attempts are rejected without even checking the password, until the window
passes.

```json
{
  "error": "Too many failed attempts. Please try again in a few minutes."
}
```

## `POST /api/v1/auth/logout`

Header required: `Authorization: Bearer <token>`. No body.

Revokes the session behind this token, so the token stops working immediately.
`200` with `{ "success": true }`, or `401` if the token is missing, invalid or
already revoked. Call it when the user signs out of the desktop app, then
discard the stored token.

## `GET /api/v1/me`

Header required: `Authorization: Bearer <token>`

Success — `200`:

```json
{
  "user": {
    "id": "uuid",
    "name": "Ada Obi",
    "email": "ada@company.com",
    "phone": "+2348000000000",
    "emailVerified": true
  },
  "organization": {
    "id": "uuid",
    "name": "Obi Distribution Ltd",
    "industry": "Wholesale",
    "currency": "NGN",
    "warehouseName": "Main warehouse — Lagos",
    "logoUrl": "https://abc123.public.blob.vercel-storage.com/logos/uuid/logo-x1y2z3.png",
    "registrationNumber": "RC 1234567",
    "address": "12 Marina Road, Lagos",
    "phone": "+2348000000000",
    "email": "office@obi.example",
    "taxName": "VAT",
    "taxRate": 7.5,
    "timezone": "Africa/Lagos",
    "dateFormat": "DD/MM/YYYY",
    "subscriptionStatus": "trial",
    "trialEndsAt": "2026-09-26T00:00:00.000Z",
    "currentPeriodEnd": null,
    "cancelAtPeriodEnd": false,
    "setupCompletedAt": null
  },
  "role": "Owner",
  "permissions": [
    "products.view",
    "products.create",
    "products.edit",
    "products.archive",
    "stock.view",
    "stock.in",
    "stock.out",
    "stock.adjust",
    "...",
    "team.manage",
    "setup.complete",
    "products.write",
    "..."
  ]
}
```

`user.emailVerified` is `false` until the person confirms the link emailed to
them at sign-up. Someone with an unconfirmed email can't create an
organization on the website, so for them `organization` is `null` and the
desktop app should ask them to check their inbox and finish on the website.
Accounts that existed before email confirmation was introduced are treated as
confirmed.

`logoUrl` is a public image URL, or `null` if the owner hasn't uploaded a
logo on the website. It can be shown directly (for example in the app header
or on printed receipts).

`subscriptionStatus` is one of `pending`, `trial`, `active`, `past_due`,
`expired`, `cancelled` or `suspended`. The company fields (`address`,
`phone`, `email`, `registrationNumber`, `taxName`) are `null` until the owner
fills them in on the website; `taxRate` defaults to `0`. `timezone` and
`dateFormat` are the organization's preferences and are meant to be used for
displaying dates in the desktop app.

`setupCompletedAt` is `null` until an Owner or Administrator finishes the
guided setup (see "Guided setup" below), then the time they did. It is
shared by the whole organization, so finishing on one computer stops the
wizard opening on every other. Organizations that already had products
when this field was added were marked as set up.

If the signed-in user hasn't created an organization yet, `organization` and
`role` come back as `null`. The desktop client should treat that as "send them
to finish setting up on the web app" rather than assuming it's an error. If
they have an organization but no active subscription, `organization` is
present and `subscriptionStatus` says why (see Subscription gating).

Failure — `401` (missing/invalid/expired token):

```json
{
  "error": "Unauthorized."
}
```

Failure — `404` (token is valid but the account no longer exists, e.g. it was
deleted after the token was issued):

```json
{
  "error": "User not found."
}
```

## Warehouses

Header required on all of these: `Authorization: Bearer <token>`.

### `GET /api/v1/warehouses`

Returns every warehouse for the organization, oldest first, including disabled
ones (`status: "inactive"`).

```json
{
  "warehouses": [
    {
      "id": "uuid",
      "organizationId": "uuid",
      "name": "Main Warehouse",
      "address": null,
      "managerName": null,
      "phone": null,
      "status": "active",
      "createdAt": "2026-09-22T19:00:00.000Z",
      "stock": { "units": 340, "products": 12, "valueAtCost": 1520000, "valueAtRetail": 1810000 }
    }
  ]
}
```

`stock` is what the warehouse holds now: total units, how many products have a
non-zero balance there, and their value at purchase and selling price.

You need an **active** `warehouseId` from this list to record a stock movement.

A warehouse can only be **disabled while it's empty**. `PATCH` with
`"status": "inactive"` on one that still holds stock is refused with `409`
and `"code": "warehouse_not_empty"` (plus `units` and `products`); the
message lists what's left. Empty it with stock out or an adjustment first
(stock transfers between warehouses come later).

### `POST /api/v1/warehouses`

```json
{ "name": "Ikeja Depot", "address": "optional", "managerName": "optional", "phone": "optional" }
```

`201` with `{ "warehouse": { ... } }`. Only `name` is required.

The plan may cap active warehouses (the default plan allows one). Creating
another at the cap returns `403` with `"code": "plan_limit"` (see "Plan
limits"); disable an existing one first.

### `PATCH /api/v1/warehouses/{id}`

Send any of `name`, `address`, `managerName`, `phone` (string or `null`) and
`status` (`"active"` or `"inactive"`). Disabling is how you retire a warehouse;
there is no delete. Re-enabling one while another is active hits the same
`plan_limit` `403`. Renaming the oldest warehouse also updates the
organization's `warehouseName`.

Failures for all three: `400` (bad input), `401`, `402`/`403` (subscription),
`404` (unknown id, or it belongs to another organization).

## Products

Header required: `Authorization: Bearer <token>`.

### `GET /api/v1/products`

Every product for the organization. Archived products are hidden unless you
add `?includeArchived=true`. Add `?supplierId=<id>` for only the products
linked to that supplier (the supplier's "products supplied"). No pagination
yet.

### `POST /api/v1/products`

```json
{
  "sku": "SKU-001",
  "name": "Bag of Rice (50kg)",
  "barcode": "1234567890123",
  "description": "optional",
  "brand": "Mama Gold",
  "category": "Grains",
  "unit": "bag",
  "purchasePrice": 30000,
  "sellingPrice": 35000,
  "minStock": 5,
  "maxStock": 200,
  "supplierId": "uuid"
}
```

Only `sku` and `name` are required; `unit` defaults to `"piece"`, prices and
`minStock` to `0`, `maxStock` to `null` (no upper limit). `201` with:

```json
{
  "product": {
    "id": "uuid",
    "organizationId": "uuid",
    "sku": "SKU-001",
    "barcode": "1234567890123",
    "name": "Bag of Rice (50kg)",
    "description": null,
    "brand": "Mama Gold",
    "imageUrl": null,
    "category": "Grains",
    "unit": "bag",
    "purchasePrice": 30000,
    "sellingPrice": 35000,
    "minStock": 5,
    "maxStock": 200,
    "currentStock": 0,
    "stockByWarehouse": [],
    "status": "active",
    "supplierId": "uuid",
    "createdAt": "2026-09-22T19:21:17.660Z",
    "updatedAt": "2026-09-22T19:21:17.660Z"
  }
}
```

Validation: prices must be non-negative numbers; `minStock`/`maxStock` must be
non-negative whole numbers and `maxStock` can't be below `minStock`. `sku` is
unique *within the organization* (`409` if reused).

`supplierId` is the product's usual supplier, or `null` (the default). It must
be an active supplier of the same organization, otherwise `400` with
`"code": "invalid_supplier"`. If that supplier is archived later, the link
stays and edits that keep it are still accepted; only *new* links to an
archived supplier are refused. Supplier names for display come from
`GET /api/v1/suppliers/options` below, so showing a product's supplier
doesn't need `suppliers.view`.

`currentStock` always starts at `0` and only ever changes through the
movements endpoint below. It is the total across warehouses;
`stockByWarehouse` lists each warehouse holding a non-zero balance, e.g.
`[{ "warehouseId": "uuid", "quantity": 60 }, { "warehouseId": "uuid", "quantity": 40 }]`.
Every endpoint that returns products includes it.

### `GET /api/v1/products/{id}`

`200` with `{ "product": { ... } }`, or `404`.

### `PATCH /api/v1/products/{id}`

Send any of `sku`, `name`, `barcode`, `description`, `brand`, `category`,
`unit`, `purchasePrice`, `sellingPrice`, `minStock`, `maxStock`, `supplierId`,
`status`.
Same validation as create. `status` is `active`, `inactive` or `archived`.
**`currentStock` can't be set here**, and sending only unknown fields is a
`400`. `409` if the new `sku` belongs to another product.

### `DELETE /api/v1/products/{id}`

Archives the product (`status: "archived"`) rather than deleting it, because
its stock movement history has to stay intact. It disappears from the default
product list; its SKU stays reserved. Returns the archived product.

### `POST /api/v1/products/{id}/image`

Uploads (or replaces) the product's picture. Send `multipart/form-data` with
one file in a field named **`image`**:

```
curl -X POST https://<host>/api/v1/products/<id>/image \
  -H "Authorization: Bearer <token>" \
  -F "image=@rice.png"
```

- PNG, JPEG or WebP only, **2 MB or smaller**. The file type is decided from
  the file's actual contents, not its name or the `Content-Type` you send, so a
  renamed file is rejected. SVG and GIF are not accepted.
- `200` with `{ "product": { ... } }`; `product.imageUrl` is now a public URL.
  Uploading again replaces the picture and the old file is deleted.
- Failures: `400` (no file in `image`, wrong type, empty file, over 2 MB),
  `413` (body clearly too large), `404` (unknown product, or another
  organization's), `401`, `402`/`403` (subscription), `502` (the storage
  service failed; nothing changed), `503` with `"code": "storage_unavailable"`
  (image storage isn't configured on the server).

`imageUrl` can only be set through this endpoint. It is ignored on product
create and rejected on `PATCH`.

### `DELETE /api/v1/products/{id}/image`

Removes the picture and deletes the stored file. Returns `{ "product": { ... } }`
with `imageUrl: null`; it's a harmless `200` if there was no image.

## Categories and units

Product categories and units of measurement are configurable per organization.
New organizations start with these units: piece, carton, bag, box, pack,
kilogram, litre, meter. Any `category` or `unit` you send when creating or
updating a product is added to the list automatically, so custom values just
work.

- `GET /api/v1/categories` and `GET /api/v1/units` return
  `{ "categories": [{ "id", "name" }] }` / `{ "units": [{ "id", "name" }] }`,
  sorted by name.
- `POST /api/v1/categories` and `POST /api/v1/units` take `{ "name": "..." }`
  (max 60 characters) and return `201`. Duplicates, ignoring case, are `409`.
- `DELETE /api/v1/categories/{id}` and `DELETE /api/v1/units/{id}` remove one.
  If products still use it you get `409` telling you how many; change those
  products first.

## Stock movements

Header required: `Authorization: Bearer <token>`. This is the *only* way
stock ever changes, so every stock change has a matching movement record.

Stock is held **per warehouse**: each product has a balance in each
warehouse (`stockByWarehouse` on the product), and `currentStock` is the
total across all warehouses. A movement changes one warehouse's balance and
the total together, in a single database statement, so the two always agree.

### `GET /api/v1/inventory/movements`

The most recent 100 movements for the organization, newest first. Add
`?productId=<uuid>` for one product's history and/or `?warehouseId=<uuid>`
for one warehouse's.

### `POST /api/v1/inventory/movements`

```json
{
  "productId": "uuid",
  "warehouseId": "uuid",
  "type": "stock_in",
  "quantity": 100,
  "reason": "optional, e.g. Initial purchase"
}
```

- `type` must be one of `stock_in`, `stock_out`, `adjustment`, `count`.
- `quantity` is a **signed whole-number delta**: positive adds stock, negative
  removes it (send `-30` to remove 30). It's applied atomically to the
  warehouse's balance and the total, so concurrent requests can't overwrite
  each other.
- A `stock_out` can't take that warehouse below zero: it's refused with
  `409` and `"code": "insufficient_stock"`, plus `available` (what the
  warehouse holds). The check runs against the locked current balance, so
  12 simultaneous one-unit stock outs against 10 units give exactly 10
  successes. `adjustment` and `count` may still go below zero, to correct
  records. For a `count`, compute the delta from the *warehouse's* balance.
- `warehouseId` must be an **active** warehouse of your organization; another
  organization's warehouse, or a disabled one, is a `404`.

`201`:

```json
{
  "movement": {
    "id": "uuid",
    "organizationId": "uuid",
    "warehouseId": "uuid",
    "productId": "uuid",
    "userId": "uuid",
    "type": "stock_in",
    "quantity": 100,
    "reason": "Initial purchase",
    "previousStock": 0,
    "newStock": 100,
    "createdAt": "2026-09-22T19:21:37.865Z"
  },
  "currentStock": 100,
  "warehouseStock": 100,
  "alert": null
}
```

`previousStock`/`newStock` and `warehouseStock` are that warehouse's balance;
`currentStock` is the product's total across warehouses.

`alert` is based on the product's **total** across warehouses: `"low_stock"`
when this movement takes the total from above its
`minStock` to at or below it, `"out_of_stock"` when it takes stock from
positive to zero or less, and `null` otherwise. It fires on the *crossing*,
not on every movement while stock stays low. The same event emails the
organization's members, listing how much each warehouse holds when there's
more than one. The desktop app can use `alert` to show a message straight
away.

Failures: `400` (invalid type, ids or quantity), `401`, `402`/`403`
(subscription or role), `404` (product or warehouse not found), `409`
(`insufficient_stock`).

## Stock alerts

### `GET /api/v1/alerts/stock`

The current picture for active products:

```json
{
  "lowStock": [ { "...": "products with 0 < currentStock <= minStock (minStock > 0)" } ],
  "outOfStock": [ { "...": "products with currentStock <= 0" } ]
}
```

Each product includes `stockByWarehouse`.

## Purchases

Header required: `Authorization: Bearer <token>`. A purchase buys products
from one supplier into one warehouse. Numbers are per organization
(`PO-0001`, `PO-0002`, ...).

Statuses: `draft` (being prepared, editable), `pending` (ordered, waiting
for delivery, still editable), `partially_received`, `received`, and
`cancelled`. Receiving is allowed from draft, pending or partially received.

What receiving does, in one all-or-nothing database step:

- adds each received quantity to that warehouse's stock (a `stock_in`
  movement with reason "Received on PO-0001" and `purchaseId` set);
- sets each product's `purchasePrice` to the unit cost just received (the
  change is in the product's audit history);
- on the **first** receipt only, puts the whole purchase `total` on the
  supplier's credit ledger as a `charge`, and anything already paid as a
  `payment` (both entries carry `purchaseId`). Later payments on the
  purchase go to the ledger as they're made.

### The purchase object

```json
{
  "id": "uuid", "number": 1, "reference": "PO-0001",
  "supplierId": "uuid", "supplierName": "Dangote Foods Ltd",
  "warehouseId": "uuid", "warehouseName": "Lagos Main",
  "status": "partially_received",
  "orderDate": "2026-10-22T09:00:00.000Z", "expectedDate": null, "notes": "Monthly order",
  "subtotal": 660000, "discount": 10000, "tax": 5000, "total": 655000,
  "amountPaid": 100000, "balance": 555000, "paymentStatus": "partial",
  "postedAt": "2026-10-22T10:00:00.000Z", "receivedAt": null, "cancelledAt": null,
  "createdBy": "uuid", "createdByName": "Ada Obi",
  "createdAt": "...", "updatedAt": "...",
  "unitsOrdered": 50, "unitsReceived": 4,
  "lines": [
    {
      "id": "uuid", "productId": "uuid", "productName": "Rice 50kg", "sku": "RICE-50", "unit": "bag",
      "quantity": 10, "unitCost": 62000, "lineTotal": 620000, "receivedQuantity": 4
    }
  ]
}
```

`total = subtotal - discount + tax`; `paymentStatus` is `unpaid`, `partial`
or `paid`. `postedAt` is when the purchase reached the supplier's account
(its first receipt).

### `GET /api/v1/purchases`

Needs `purchases.view`. Newest first, with lines. Filters: `?status=` (one
status, or `open` for draft + pending + partially received),
`?supplierId=`, `?warehouseId=`, `?limit=` (default 100, max 200).

### `GET /api/v1/purchases/{id}`

The purchase plus `receipts` (`[{ id, createdAt, userName, lines: [{ productId,
quantity }] }]`) and `payments` (`[{ id, amount, note, createdAt, userName }]`).

### `POST /api/v1/purchases`

Needs `purchases.create`.

```json
{
  "supplierId": "uuid",
  "warehouseId": "uuid",
  "lines": [{ "productId": "uuid", "quantity": 10, "unitCost": 61000 }],
  "status": "pending",
  "orderDate": "2026-10-22",
  "expectedDate": "2026-10-29",
  "notes": "optional",
  "discount": 10000,
  "tax": 5000,
  "amountPaid": 0,
  "receive": false,
  "clientRef": "optional, makes a retry harmless"
}
```

Required: `supplierId` (an active supplier), `warehouseId` (an active
warehouse) and at least one line (a product that isn't archived, a whole
quantity above 0, a unit cost of 0 or more). `status` is `draft` (default)
or `pending`. `amountPaid` above 0 also needs `credit.record` and can't
exceed the total. `"receive": true` (needs `purchases.receive`) receives
everything straight away, for goods bought and collected on the spot. The
same `clientRef` again returns the purchase already recorded with
`"duplicate": true`. `201` with `{ "purchase": { ... } }`.

Errors: `400` with `code` `invalid_supplier`, `invalid_warehouse`,
`invalid_product` or `overpayment`, or a validation message; `403`
`forbidden_role`.

### `PATCH /api/v1/purchases/{id}`

Needs `purchases.create`. Any of `supplierId`, `warehouseId`, `status`
(`draft` or `pending`, i.e. place or un-place the order), `orderDate`,
`expectedDate`, `notes`, `discount`, `tax`, `lines` (replaces all
lines). Only while it's draft or pending and nothing has been received;
otherwise `409` `purchase_locked`. The total can't drop below what has
already been paid (`409` `overpayment`).

### `POST /api/v1/purchases/{id}/receive`

Needs `purchases.receive`. `{ "lines": [{ "lineId": "uuid", "quantity": 4 }] }`
for what arrived, or `{ "all": true }` for everything outstanding; optional
`clientRef`. Returns `{ purchase, priceChanges: [{ productId, previous, new }],
duplicate }`. Errors (`409` unless noted): `over_receipt` (more than is
outstanding; includes `lineId` and `remaining`), `purchase_not_receivable`
(received or cancelled), `warehouse_inactive`, `line_not_found` (`400`),
`invalid_quantity` (`400`). Two people receiving the same purchase at the
same moment can't over-receive it: the second is checked against what the
first left.

### `POST /api/v1/purchases/{id}/payments`

Needs `purchases.view` and `credit.record`. `{ "amount": 555000, "note":
"Bank transfer", "clientRef": "optional" }`. `201` with `{ purchase }`.
`409` `overpayment` (includes `remaining`) or `purchase_cancelled`.

### `POST /api/v1/purchases/{id}/cancel`

Needs `purchases.cancel`. Only a draft or pending purchase with nothing
received (`409` `purchase_not_cancellable` otherwise). If money was paid on
it, that amount goes on the supplier's account as a negative `adjustment`
(the supplier owes it back), and the response's `refundOwed` says how much.

## Sales

Header required: `Authorization: Bearer <token>`. A sale sells products to a
customer (or a walk-in) from one warehouse. It is completed the moment it is
recorded: the stock leaves the warehouse at once. Numbers are per
organization (`INV-0001`, `INV-0002`, ...). The only later change is
voiding it.

Recording a sale, in one all-or-nothing database step:

- takes each line's quantity out of the warehouse (a `stock_out` movement,
  reason "Sold on INV-0001", `saleId` set). A sale can't take a warehouse
  below zero: one short line refuses the whole sale;
- keeps each line's `listPrice` (the product's selling price then) and its
  cost (purchase price then, for profit reports);
- for a named customer, puts the sale `total` on their credit ledger as a
  `charge` and anything paid at the counter as a `payment` (both with
  `saleId`), so their statement shows cash sales too.

### The sale object

```json
{
  "id": "uuid", "number": 1, "reference": "INV-0001",
  "customerId": "uuid", "customerName": "Ada Stores",
  "warehouseId": "uuid", "warehouseName": "Lagos Main",
  "status": "completed",
  "saleDate": "2026-10-26T10:00:00.000Z", "notes": null,
  "subtotal": 140000, "discount": 0, "tax": 0, "total": 140000,
  "amountPaid": 100000, "balance": 40000, "paymentStatus": "partial",
  "overLimit": false, "voidedAt": null, "voidReason": null,
  "createdBy": "uuid", "createdByName": "Tunde", "createdAt": "...",
  "units": 2,
  "lines": [
    {
      "id": "uuid", "productId": "uuid", "productName": "Rice 50kg", "sku": "RICE-50", "unit": "bag",
      "quantity": 2, "unitPrice": 70000, "listPrice": 70000, "lineTotal": 140000
    }
  ]
}
```

`customerId` is `null` (and `customerName` "Walk-in customer") for a walk-in
sale. `paymentStatus` is `unpaid`, `partial`, `paid`, or `voided`.
`overLimit` is true when an Owner or Administrator allowed it over the
customer's credit limit. `GET /sales/{id}` adds `payments`
(`[{ id, amount, method, note, createdAt, userName }]`).

### `GET /api/v1/sales`

Needs `sales.view`. Newest first, with lines. Filters: `?status=completed`,
`voided` or `unpaid` (completed with a balance), `?customerId=`,
`?warehouseId=`, `?from=` and `?to=` (sale date), `?limit=` (default 100,
max 200).

### `POST /api/v1/sales`

Needs `sales.create`.

```json
{
  "customerId": "uuid or null",
  "warehouseId": "uuid",
  "lines": [{ "productId": "uuid", "quantity": 2, "unitPrice": 70000 }],
  "discount": 0,
  "tax": 0,
  "amountPaid": 140000,
  "paymentMethod": "cash",
  "saleDate": "optional",
  "notes": "optional",
  "allowOverLimit": false,
  "clientRef": "optional, makes a retry harmless"
}
```

- `unitPrice` defaults to the product's selling price. A different price,
  or a `discount` above 0, needs `sales.discount` (`403 forbidden_role`).
- `amountPaid` defaults to the total (a cash sale). `paymentMethod` is one of
  `cash`, `transfer`, `pos`, `card`, `cheque`, `other`. Taking payment at
  the counter is part of selling; later payments need `credit.record`.
- A walk-in sale (`customerId: null`) must be paid in full: `400`
  `walk_in_must_pay` otherwise.
- If the unpaid part would take the customer over their `creditLimit` (0
  means no limit), it is refused with `409 over_credit_limit` and
  `available` (credit left). `"allowOverLimit": true` (needs
  `sales.override`) records it anyway, flagged `overLimit`.
- `409 insufficient_stock` (with `productId`, `name`, `available`) when the
  warehouse doesn't hold enough; `409 warehouse_inactive`; `400
  invalid_customer` / `invalid_product`.

`201` with `{ sale, alerts: [{ productId, alert }] }`: `alert` is
`low_stock` or `out_of_stock` when the sale took a product's total across
that line, and the organization is emailed as with stock movements. The
same `clientRef` again returns the sale already recorded with
`"duplicate": true`. Two sellers taking the last units at the same moment
can't oversell: the second is checked against what the first left.

### `POST /api/v1/sales/{id}/payments`

Needs `sales.view` and `credit.record`. `{ "amount": 40000, "method": "pos",
"note": "optional", "clientRef": "optional" }`. Also a payment on the
customer's account. `409 overpayment` (with `remaining`) or `sale_voided`.

### `POST /api/v1/sales/{id}/void`

Needs `sales.void`. `{ "reason": "Wrong customer" }` (required). Every line's
stock goes back to the warehouse (`stock_in`, "Voided INV-0001") and the
sale comes off the customer's account (an `adjustment` of minus the total),
so money already paid stays as a credit owed back to them: the response's
`refundOwed`. `409 sale_not_voidable` if already voided.

## Reports

### `GET /api/v1/reports/valuation`

Needs `products.view` and `stock.view`. What the organization's stock is
worth right now: every warehouse balance priced at the product's **current**
purchase price (`valueAtCost`) and selling price (`valueAtRetail`). Past
purchase costs aren't recorded yet, so there is no average or FIFO cost.

Optional `?warehouseId=<uuid>` and `?category=<name>` narrow every section,
totals included (`?category=` with nothing after it means uncategorised).

```json
{
  "asOf": "2026-10-21T10:00:00.000Z",
  "basis": "current_purchase_price",
  "filters": { "warehouseId": null, "category": null },
  "totals": {
    "products": 4, "units": 40,
    "valueAtCost": 1042000, "valueAtRetail": 1129000,
    "margin": 87000, "marginPercent": 7.71
  },
  "byProduct": [
    {
      "productId": "uuid", "sku": "RICE-50", "name": "Rice 50kg",
      "category": "Grains", "unit": "bag", "quantity": 12,
      "unitCost": 61000, "unitPrice": 65000,
      "valueAtCost": 732000, "valueAtRetail": 780000, "margin": 48000,
      "warehouses": [{ "warehouseId": "uuid", "quantity": 10 }, { "warehouseId": "uuid", "quantity": 2 }],
      "flags": []
    }
  ],
  "byCategory": [
    { "category": "Grains", "products": 2, "units": 15, "valueAtCost": 822000, "valueAtRetail": 879000, "margin": 57000, "marginPercent": 6.48 }
  ],
  "byWarehouse": [
    { "warehouseId": "uuid", "name": "Lagos", "status": "active", "products": 3, "units": 19, "valueAtCost": 730000, "valueAtRetail": 779000, "margin": 49000, "marginPercent": 6.29 }
  ],
  "warnings": { "negativeStock": 1, "noCost": 1 }
}
```

Only products holding stock appear. `byProduct` is sorted by value at cost,
highest first. `margin` is `valueAtRetail - valueAtCost`, and
`marginPercent` is that as a share of `valueAtRetail` (`null` when there
is nothing to sell). `flags` marks rows that make a valuation unreliable:
`negative_stock` (some warehouse is below zero), `no_cost` (purchase price
is 0) and `archived` (archived but still holding stock, still counted).
`category: null` means uncategorised. Subtotals by category and by warehouse
always add up to `totals`.

## Customers and suppliers

Header required on all of these: `Authorization: Bearer <token>`. The two
resources have the same shape, so they are described together; each has its
own paths and permissions (`customers.view`, `.create`, `.edit`, `.archive`
and the same for `suppliers`).

### `GET /api/v1/suppliers/options`

Every supplier's id, name and status (`active` or `archived`), sorted by
name, for showing and picking a product's supplier. Open to anyone with
`products.view` or `suppliers.view`; it never includes balances or contact
details.

```json
{ "suppliers": [{ "id": "uuid", "name": "Dangote Foods Ltd", "status": "active" }] }
```

### Customer and supplier records

- `GET /api/v1/customers` and `GET /api/v1/suppliers` return
  `{ "customers": [...] }` / `{ "suppliers": [...] }`, sorted by name, archived
  ones hidden unless you add `?includeArchived=true`. Every row carries
  `balanceOwed` (see the credit ledger below).
- `POST` creates one (`201`, `{ "customer": { ... } }` or `{ "supplier": { ... } }`).
  Only `name` is required.
- `GET /{id}` returns one, `PATCH /{id}` changes any of the fields, and
  `DELETE /{id}` **archives** it (`status: "archived"`) rather than deleting,
  because its credit history has to stay intact.

Fields: `name` (max 200), `phone`, `email`, `address`, `notes` (optional text,
`null` clears), plus `contactPerson` on suppliers only, and on customers only
`creditLimit` (a non-negative number) and `customerTypeId` (one of the
organization's customer types, or `null`). Sending a field the other resource
owns is a `400`; an unknown or another organization's type is a `400`.

A new customer given a type but no `creditLimit` takes the type's
`defaultCreditLimit` (otherwise `0`). Changing a customer's type later never
changes their limit.

`PATCH` with `"status": "active"` restores an archived record (needs
`.archive`; logged as `customer.restored` / `supplier.restored`).

Customers also carry, read-only: `customerTypeName` (`null` without a type),
and what they have bought on completed sales (voided ones don't count):
`totalSales`, `salesCount` and `lastSaleAt` (`null` if none).

```json
{
  "customer": {
    "id": "uuid",
    "organizationId": "uuid",
    "name": "Blessing Retail Store",
    "phone": "+234 706 555 0201",
    "email": null,
    "address": null,
    "notes": null,
    "creditLimit": 200000,
    "customerTypeId": "uuid",
    "status": "active",
    "createdAt": "2026-09-27T09:00:00.000Z",
    "updatedAt": "2026-09-27T09:00:00.000Z",
    "balanceOwed": 45000,
    "customerTypeName": "Retail",
    "totalSales": 1250000,
    "salesCount": 14,
    "lastSaleAt": "2026-10-25T15:04:00.000Z"
  }
}
```

### Customer types

Each organization keeps its own list. New organizations (and every
organization that existed when types were added) start with Retail,
Wholesale, Distributor and Corporate.

- `GET /api/v1/customer-types` (`customers.view`):
  `{ "customerTypes": [{ "id", "name", "defaultCreditLimit", "customerCount" }] }`
  sorted by name. `customerCount` includes archived customers.
- `POST /api/v1/customer-types` (`customers.types`) with
  `{ "name": "Agents", "defaultCreditLimit": 100000 }` → `201`
  `{ "customerType": {...} }`. `name` is required (max 60); a name already
  used (any case) is a `409`. `defaultCreditLimit` is optional (default `0`).
- `PATCH /api/v1/customer-types/{id}` (`customers.types`) changes `name` and/or
  `defaultCreditLimit`. A new default only applies to customers added later.
- `DELETE /api/v1/customer-types/{id}` (`customers.types`) removes it, or `409`
  `{ "code": "type_in_use", "customerCount": 3 }` while any customer
  (archived included) still has it.

Failures: `400` (bad input), `401`, `402`/`403` (subscription, or
`forbidden_role`), `404` (unknown id, or another organization's).

## Credit ledger

One ledger for both sides of a wholesaler's credit: a customer's balance is
what they owe you, a supplier's balance is what you owe them. A positive
`balanceOwed` always means "still owed". Every entry you post is kept
(nothing is ever overwritten), and the party's `balanceOwed` is moved by one
atomic update per entry - so two people recording payments on the same party
at once, or offline changes synced later, can never both be accepted past
what's actually owed. The `overpayment` check below is enforced by that same
atomic update, not a separate read, so it holds even under real concurrency.

### `GET /api/v1/credit-entries`

Newest first, up to `?limit=` (default 100, max 1000). Filter with
`?partyType=customer|supplier` and `?partyId=<uuid>`. Without a `partyType` you
get the ledgers your role may read (a Sales Staff member sees only the customer
ledger); asking for a type you can't read is a `403`.

For statements, `?from=` and `?to=` (ISO dates or date-times) limit the
entries to that period: `from` inclusive, `to` exclusive. With a `partyType`,
a `partyId` and a `from`, the response also has `openingBalance`: what was
owed before `from`, so the opening balance plus the period's entries is the
balance at the end of the period. `400` if a date can't be read.

### `POST /api/v1/credit-entries`

Needs `credit.record`.

```json
{
  "partyType": "customer",
  "partyId": "uuid",
  "kind": "payment",
  "amount": 15000,
  "note": "Part payment, cash",
  "clientRef": "3f6c1a9e-optional-unique-id"
}
```

- `kind` is `charge` (a sale on credit or a supplier invoice: raises the
  balance), `payment` (lowers it) or `adjustment` (a signed correction).
- `amount` is positive for `charge` and `payment`; the server applies the sign.
  For `adjustment` it is signed and non-zero.
- A payment larger than the balance owed is refused with `400` and
  `"code": "overpayment"` (with the current `balanceOwed`).
- **`clientRef`** makes a retry harmless. Send a unique value per entry; if a
  request with the same `clientRef` already succeeded (for example an offline
  change sent again after the answer was lost), you get `200` with the
  existing entry and `"duplicate": true` instead of a second entry.

`201` (or `200` for a duplicate):

```json
{
  "entry": {
    "id": "uuid",
    "organizationId": "uuid",
    "partyType": "customer",
    "partyId": "uuid",
    "kind": "payment",
    "amount": -15000,
    "note": "Part payment, cash",
    "userId": "uuid",
    "clientRef": "3f6c1a9e-optional-unique-id",
    "createdAt": "2026-09-27T09:05:00.000Z"
  },
  "balanceOwed": 30000
}
```

Entries are stored signed (`amount: -15000` for a payment). Archived parties
keep their ledger and can still be paid off.

## Guided setup

The desktop app walks a new organization's Owner or Administrator through
warehouse, products, opening stock, team and subscription. Each step uses
the endpoints in this document (opening stock is a `stock_in` movement with
the reason `Opening stock`). When they finish, the app calls:

### `POST /api/v1/organization/setup`

Needs `setup.complete`. No body. Sets `setupCompletedAt` and returns it:

```json
{ "setupCompletedAt": "2026-10-21T09:12:44.120Z" }
```

Calling it again is harmless: it returns the original time and doesn't
change it. The first call is recorded in the activity trail.

## Team

### `GET /api/v1/team`

Needs `team.manage`. Returns the members, pending invitations, the roles the
caller may invite, and seat use (`limit` is `null` when the plan has no cap;
`used` counts members plus pending invitations, which is what the plan limit
checks):

```json
{
  "members": [
    {
      "id": "uuid",
      "name": "Ada Obi",
      "email": "ada@obi.example",
      "role": "Owner",
      "joinedAt": "2026-09-20T10:00:00.000Z"
    }
  ],
  "invitations": [
    {
      "id": "uuid",
      "email": "tunde@obi.example",
      "role": "Sales Staff",
      "expiresAt": "2026-10-28T09:00:00.000Z",
      "createdAt": "2026-10-21T09:00:00.000Z",
      "invitedByName": "Ada Obi"
    }
  ],
  "assignableRoles": ["Owner", "Administrator", "Warehouse Manager", "Sales Staff", "Inventory Staff", "Accountant / Finance"],
  "seats": { "limit": 5, "used": 2 }
}
```

An Administrator's `assignableRoles` leaves out Owner and Administrator.

### `POST /api/v1/team/invitations`

Needs `team.manage`, and the caller's email must be confirmed. Body:

```json
{ "email": "tunde@obi.example", "role": "Sales Staff" }
```

Emails a 7-day invitation link, exactly like the website's Team page. Success
— `201`:

```json
{
  "invitation": { "id": "uuid", "email": "tunde@obi.example", "role": "Sales Staff" },
  "emailSent": true
}
```

If `emailSent` is `false` the invitation was saved but the email didn't go
out; it can be resent from the website's Team page.

| Status | `code` | Meaning |
|---|---|---|
| 400 | `invalid_request` | `email` or `role` missing |
| 400 | `invalid_email` | Not a valid email address |
| 403 | `email_unverified` | The caller hasn't confirmed their own email |
| 403 | `role_not_assignable` | Unknown role, or one the caller can't give (Administrators can't invite Owners or Administrators) |
| 403 | `plan_limit` | The plan's team size is reached (members plus pending invitations) |
| 409 | `too_many_pending` | 25 invitations are already pending |
| 409 | `already_in_organization` | That person already belongs to an organization on Aimify |
| 429 | `rate_limited` | More than 20 invitations in the last hour |

Changing roles, removing members and revoking invitations stay on the
website's Team page.

## What this API does *not* do yet

- **No expenses yet.** They are still saved on the desktop only.
- **No returns yet** (Phase 2). A sale recorded by mistake can be voided.
- **No stock transfers between warehouses yet.** Moving stock means a stock
  out in one warehouse and a stock in to the other.
- **Plan limits are configured by the Aimify team.** The default plan allows
  one active warehouse and is otherwise unlimited; see "Plan limits" above.

## Where this lives, if it needs to change

All of this is implemented in the `aimify-web` repo:

- `lib/credentials.ts` — shared password verification (also used by the web
  login)
- `lib/api-auth.ts` — JWT creation/verification
- `lib/org.ts` — `getOrgContextForUser(userId)`, which also expires trials
- `lib/api-context.ts` — `getApiOrgContext` (token to organization) and
  `guardApi`, which adds the subscription check every gated route uses
- `lib/subscription.ts` — statuses, which ones unlock the desktop app, and the
  user-facing messages
- `lib/images.ts`, `lib/blob.ts` — image validation (by file contents) and
  storage in Vercel Blob for company logos and product images
- `lib/product-input.ts`, `lib/warehouse-input.ts`, `lib/catalog.ts`,
  `lib/catalog-routes.ts`, `lib/stock-alerts.ts`, `lib/plans.ts` —
  validation and rules behind the endpoints above
- `app/api/v1/` — `auth/login`, `me`, `warehouses` (+ `[id]`), `products`
  (+ `[id]`), `categories` (+ `[id]`), `units` (+ `[id]`), `alerts/stock`,
  `inventory/movements`, `customers` (+ `[id]`), `suppliers` (+ `[id]`),
  `credit-entries`
- `lib/party-routes.ts`, `lib/party-input.ts`, `lib/credit.ts` — the shared
  customer/supplier handlers, their validation, and the ledger arithmetic
- `db/schema.ts` — `warehouses`, `products`, `stock_movements`,
  `catalog_options`, `customers`, `suppliers`, `credit_entries` tables

New endpoints get added under `app/api/v1/` and should start with
`guardApi(request)`.
