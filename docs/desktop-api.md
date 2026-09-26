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
After the subscription check, write endpoints check the role. A role that isn't
allowed gets `403`:

```json
{
  "error": "Your role (Sales Staff) isn't allowed to do this.",
  "code": "forbidden_role",
  "role": "Sales Staff",
  "permission": "products.write"
}
```

`/me` also returns `permissions`, the list the signed-in role holds, so the
desktop app can hide or disable controls instead of waiting for a `403`.
Reading (products, warehouses, categories, units, movements, alerts) is open
to every role.

| Permission | Covers | Roles |
|---|---|---|
| `products.write` | Create and edit products, upload or remove product images | Owner, Administrator, Warehouse Manager, Inventory Staff |
| `products.archive` | Archive a product | Owner, Administrator, Warehouse Manager |
| `catalog.write` | Add or delete categories and units | Owner, Administrator, Warehouse Manager, Inventory Staff |
| `warehouses.manage` | Create, edit and disable warehouses | Owner, Administrator, Warehouse Manager |
| `stock.out` | Record a `stock_out` movement | The roles above plus Sales Staff |
| `stock.adjust` | Record `stock_in`, `adjustment` and `count` movements | Owner, Administrator, Warehouse Manager, Inventory Staff |

Accountant / Finance is read-only. The role rules live in
`lib/permissions.ts` in `aimify-web`.

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
    "trialEndsAt": "2026-09-26T00:00:00.000Z"
  },
  "role": "Owner",
  "permissions": [
    "products.write",
    "products.archive",
    "catalog.write",
    "warehouses.manage",
    "stock.out",
    "stock.adjust"
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
      "createdAt": "2026-09-22T19:00:00.000Z"
    }
  ]
}
```

You need an **active** `warehouseId` from this list to record a stock movement.

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
add `?includeArchived=true`. No pagination yet.

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
  "maxStock": 200
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
    "status": "active",
    "createdAt": "2026-09-22T19:21:17.660Z",
    "updatedAt": "2026-09-22T19:21:17.660Z"
  }
}
```

Validation: prices must be non-negative numbers; `minStock`/`maxStock` must be
non-negative whole numbers and `maxStock` can't be below `minStock`. `sku` is
unique *within the organization* (`409` if reused).

`currentStock` always starts at `0` and only ever changes through the
movements endpoint below.

### `GET /api/v1/products/{id}`

`200` with `{ "product": { ... } }`, or `404`.

### `PATCH /api/v1/products/{id}`

Send any of `sku`, `name`, `barcode`, `description`, `brand`, `category`,
`unit`, `purchasePrice`, `sellingPrice`, `minStock`, `maxStock`, `status`.
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
`currentStock` on a product ever changes, so every stock change has a
matching movement record.

### `GET /api/v1/inventory/movements`

The most recent 100 movements for the organization, newest first. Add
`?productId=<uuid>` for one product's history.

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
  removes it (send `-30` to remove 30). It's applied as one atomic database
  update (`current_stock = current_stock + quantity`), so concurrent requests
  can't overwrite each other. 25 simultaneous requests were tested against one
  product with zero lost updates.
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
  "alert": null
}
```

`alert` is `"low_stock"` when this movement takes the product from above its
`minStock` to at or below it, `"out_of_stock"` when it takes stock from
positive to zero or less, and `null` otherwise. It fires on the *crossing*,
not on every movement while stock stays low. The same event emails the
organization's members. The desktop app can use `alert` to show a message
straight away.

Failures: `400` (invalid type, ids or quantity), `401`, `402`/`403`
(subscription), `404` (product or warehouse not found).

## Stock alerts

### `GET /api/v1/alerts/stock`

The current picture for active products:

```json
{
  "lowStock": [ { "...": "products with 0 < currentStock <= minStock (minStock > 0)" } ],
  "outOfStock": [ { "...": "products with currentStock <= 0" } ]
}
```

## What this API does *not* do yet

- **No customers, suppliers, purchases, sales or expenses.** Products and
  stock movements are the first slice; everything else builds on them.
- **No supplier link on products.** It needs a suppliers table, which doesn't
  exist in `aimify-web` yet.
- **No per-warehouse stock balances.** `currentStock` is organization-wide on
  the product; movements record which warehouse they happened in, but stock
  isn't split by warehouse. This has to change before multiple warehouses are
  offered.
- **Plan limits are configured by the Aimify team.** The default plan allows
  one active warehouse and is otherwise unlimited; see "Plan limits" above.
- **No online payments.** Subscription status changes to `active` are done by
  the Aimify team for now.

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
  `inventory/movements`
- `db/schema.ts` — `warehouses`, `products`, `stock_movements`,
  `catalog_options` tables

New endpoints get added under `app/api/v1/` and should start with
`guardApi(request)`.
