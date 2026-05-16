# Server recording (LiveKit Egress)

Production path for **full-room audio** when the client cannot mix remote LiveKit tracks (e.g. **Android**). The LiveKit server composites all participants in the room and uploads **OGG** to S3.

## Prerequisites

1. **LiveKit server** with **Redis** (see `livekit/livekit.yaml`).
2. **LiveKit Egress** service running and connected to the same Redis + LiveKit (see `docker-compose.yml` → `livekit-egress`).
3. Backend env: `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, `LIVEKIT_URL` (or `LIVEKIT_HTTP_URL` for the Twirp API, e.g. `http://livekit:7880` in Docker).
4. Same **AWS** credentials as browser uploads (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_S3_BUCKET_NAME`, `AWS_REGION`).

Deploy after changes:

```bash
docker compose up -d --build
```

On an existing server, add Redis to `livekit.yaml`, start `redis` + `livekit-egress`, and run `prisma migrate deploy` on the backend.

## API

### Admin (dashboard / admin app)

| Method | Path | Auth |
|--------|------|------|
| `POST` | `/api/recordings/egress/start` | Admin JWT |
| `POST` | `/api/recordings/egress/stop` | Admin JWT |

### Listener (mobile app)

| Method | Path | Auth |
|--------|------|------|
| `POST` | `/api/user/recordings/egress/start` | User JWT |
| `POST` | `/api/user/recordings/egress/stop` | User JWT |

### Start

```http
POST …/egress/start
Authorization: Bearer <token>
Content-Type: application/json

{
  "roomId": "<uuid>",
  "recordingName": "Session capture"
}
```

**201** example:

```json
{
  "recordingId": "…",
  "egressId": "EG_…",
  "upload": { "mode": "egress", "mimeType": "audio/ogg" },
  "data": { "recordingSource": "egress", "livekitEgressId": "EG_…", … }
}
```

- `roomId` is the **LiveKit room name** (same UUID used in `/api/livekit/token`).
- Only **one** active egress per room at a time (**409** if already recording).

### Stop

```http
POST …/egress/stop
Authorization: Bearer <token>
Content-Type: application/json

{ "recordingId": "<uuid from start>" }
```

**200** — recording `status` becomes `completed`; file is in S3 at `data.s3Key` (`.ogg`). Use `GET /api/user/recordings/:id` or admin `GET /api/recordings/:id` for `downloadUrl`.

## Mobile flow (recommended)

1. User joins room (LiveKit token as today).
2. `POST /api/user/recordings/egress/start` when user taps Record.
3. `POST /api/user/recordings/egress/stop` when done.
4. Poll or `GET` recording until `status === "completed"`, then use `downloadUrl`.

No multipart upload, no `MediaRecorder`, no S3 CORS from the app.

## Web admin

- **Browser mix** (existing): `RecordingControl` default — `MediaRecorder` + multipart.
- **Server egress**: pass `recordingMode="egress"` to `RecordingControl`, or call the admin egress endpoints from your UI.

## Errors

| Status | Meaning |
|--------|---------|
| 503 | LiveKit or S3 env missing |
| 502 | Egress service unreachable or start/stop failed |
| 409 | Egress already active for this room |
| 403 | Wrong tenant / not owner |

## vs browser recording

| | Browser (`recordingSource: browser`) | Egress (`egress`) |
|--|--------------------------------------|-------------------|
| Where mixed | Client | LiveKit server |
| Format | webm | ogg |
| Android remote audio | Not reliable | Yes |
| S3 upload | Client multipart | Egress → S3 |
