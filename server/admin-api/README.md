# admin-api

Small server-side admin API for Supabase admin operations.

## Setup

1. `cd server/admin-api`
2. `npm install`
3. Copy `.env.example` to `.env`
4. Set values in `.env`:
   - `SUPABASE_URL`
   - `SUPABASE_SECRET_KEY` (preferred) or `SUPABASE_SERVICE_ROLE_KEY`
   - `ADMIN_API_TOKEN` (strong random value, at least 32 chars)
5. Start: `npm run dev`

## Endpoints

- `GET /health`
- `POST /admin/users/create`

Request header for admin endpoint:

- `x-admin-token: <ADMIN_API_TOKEN>`

Request body:

```json
{
  "email": "dev1@example.com",
  "password": "StrongPass123",
  "username": "dev1",
  "emailConfirmed": true
}
```

## Security Defaults

- Local-only admin access unless `ALLOW_REMOTE_ADMIN=true`.
- Constant-time token comparison.
- Rate-limited create-user endpoint.
- No raw internal error leakage.
