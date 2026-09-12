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
3. The token is a stateless JWT (HS256, 30-day expiry). There is no
   server-side revocation yet — "logging out" on the client just means
   discarding the stored token locally. Once it expires, log in again.

The user must already have an Aimify account (created via the web app's
`/signup`) before they can log in from the desktop client — this API does not
currently expose account creation.

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
  "password": "your-password"
}
```

Success — `200`:

```json
{
  "token": "eyJhbGciOiJIUzI1NiJ9...."
}
```

Failure — `400` (missing fields) or `401` (wrong email/password):

```json
{
  "error": "Invalid email or password."
}
```

## `GET /api/v1/me`

Header required: `Authorization: Bearer <token>`

Success — `200`:

```json
{
  "user": {
    "id": "uuid",
    "name": "Ada Obi",
    "email": "ada@company.com",
    "phone": "+2348000000000"
  },
  "organization": {
    "id": "uuid",
    "name": "Obi Distribution Ltd",
    "industry": "Wholesale",
    "currency": "NGN",
    "warehouseName": "Main warehouse — Lagos",
    "subscriptionStatus": "trial",
    "trialEndsAt": "2026-09-26T00:00:00.000Z"
  },
  "role": "Owner"
}
```

If the signed-in user hasn't finished onboarding yet (no organization created,
or no active subscription), `organization` and `role` come back as `null`.
The desktop client should treat that as "send them to finish onboarding on
the web app" rather than assuming it's an error.

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

## What this API does *not* do yet

This is the important part for scoping desktop work realistically: the
database only has `users`, `organizations`, `memberships`, and `audit_logs`
right now. There is no products/inventory/purchases/sales/customers/
suppliers/expenses schema yet — so there's nothing for the API to expose
beyond identity and organization info.

Practical implication: the desktop app's login screen + "which organization
am I in" screen are fully buildable against this API today. Anything beyond
that (an actual inventory screen, a sales screen, etc.) needs the schema and
matching endpoints designed first, back in `aimify-web`.

## Where this lives, if it needs to change

All of this is implemented in the `aimify-web` repo:

- `lib/credentials.ts` — shared password verification (also used by the web
  login)
- `lib/api-auth.ts` — JWT creation/verification (`createApiToken`,
  `verifyApiToken`)
- `lib/org.ts` — `getOrgContextForUser(userId)` is the query `/me` uses
- `app/api/v1/auth/login/route.ts`
- `app/api/v1/me/route.ts`

New endpoints (e.g. once an inventory schema exists) get added under
`app/api/v1/`, each verifying its own Bearer token via `verifyApiToken` the
same way `/me` does.
