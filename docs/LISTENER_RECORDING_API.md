# Listener (user) recording API

For **mobile / native app** developers. This is **not** the admin dashboard API.

**Base URL:** `{API_BASE}/api/user/recordings`  
Example: `https://api.rapidvoice.pro/api/user/recordings`

> **Android / full-room capture:** Use **server recording (LiveKit Egress)** — see [EGRESS_RECORDING.md](./EGRESS_RECORDING.md). Client-side mix + multipart below is for WebView/desktop only.

---

## Authentication

All requests:

```http
Authorization: Bearer <JWT>
```

- JWT from **user** login: `POST /api/auth/user/login`
- Token payload must include **`id`** (user id), **`adminId`** (tenant), and **`role`: `user`**.

---

## Endpoints

| Method | Path | Description |
|--------|------|----------------|
| `POST` | `/egress/start` | **Server recording** — LiveKit composites room → S3 (recommended on Android) |
| `POST` | `/egress/stop` | Stop server recording (`body: { "recordingId" }`) |
| `POST` | `/start` | Start session + S3 multipart upload (browser / WebView) |
| `GET` | `/:recordingId/multipart/presign?partNumber=N` | Presigned **PUT** URL for part `N` |
| `POST` | `/:recordingId/multipart/complete` | Complete multipart upload |
| `GET` | `/:recordingId` | Recording row + presigned **`downloadUrl`** when completed |
| `POST` | `/:recordingId/cancel` | Cancel in-progress recording |
| `DELETE` | `/:recordingId` | Delete recording and S3 object |

---

## Server recording flow (egress)

1. **`POST /egress/start`** — same body as `/start` (`roomId`, `recordingName`).
2. **`POST /egress/stop`** — `{ "recordingId": "<id from start>" }`.
3. **`GET /:recordingId`** — `downloadUrl` when `status` is `completed`.

Details: [EGRESS_RECORDING.md](./EGRESS_RECORDING.md).

---

## Browser recording flow (multipart)

1. **`POST /start`** — Body:

   ```json
   {
     "roomId": "<uuid>",
     "recordingName": "My capture"
   }
   ```

   - `roomId` must belong to the same admin as `token.adminId`.

   Response **201** includes **`recordingId`** and `upload: { "mode": "multipart", "mimeType": "audio/webm" }`.

2. **Capture audio** — Client mixes listener mic + remote room audio (your implementation). Encode as **`audio/webm`** (same as web reference: `MediaRecorder`).

3. **Multipart upload to S3**
   - Each part except the last must be **≥ 5,242,880 bytes (5 MiB)**.
   - For part 1, 2, 3, …:
     - `GET /:recordingId/multipart/presign?partNumber=N`
     - `PUT` the raw bytes to the returned **`url`**
     - Store **`ETag`** from the response (required for complete).
   - Upload the remaining buffer as the **last** part (may be &lt; 5 MiB).

4. **`POST /:recordingId/multipart/complete`** — Body:

   ```json
   {
     "parts": [
       { "PartNumber": 1, "ETag": "<value from PUT response>" },
       { "PartNumber": 2, "ETag": "..." }
     ]
   }
   ```

   Strip extra quotes around `ETag` if needed.

5. **`GET /:recordingId`** — Use **`downloadUrl`** for a time-limited GET of the file (when `status` is `completed`).

6. **Cancel** — `POST /:recordingId/cancel` if the user abandons before complete.

---

## Browser / WebView and S3

If the client uses **`fetch`** / browser **`PUT`** to the presigned URL, the **S3 bucket** must have **CORS** configured for your **web origin**, allow **`PUT`**, and **expose `ETag`**. Native HTTP stacks typically ignore browser CORS.

---

## Common errors

| Status | Meaning |
|--------|--------|
| 401 | Invalid or non-user token, or missing `adminId` in JWT |
| 403 | Wrong room for tenant; or recording not owned by this user |
| 404 | Unknown `roomId` or `recordingId` |
| 400 | Bad state (e.g. not `recording`), invalid `partNumber`, empty `parts` |

---

## Separation from admin API

- **Listeners:** `/api/user/recordings` + **user** JWT  
- **Admins:** `/api/recordings` + **admin** JWT  

Do not call admin recording endpoints from the listener app.
