# Zero-Clean: Firebase Migration Plan (Essentials)

Migrate from **local phone storage + SQLite** to **Firebase Firestore** (database) and **Firebase Storage** (processed images only). No code here—design and cost only.

**Before first run (login):** In Firebase Console → Authentication → Sign-in method, enable **Email/Password**. Create users manually (no sign-up in the app).

**Before first run (Firestore + Storage):** In Firebase Console create a **Firestore database** (Native mode) and enable **Storage**. Deploy Security Rules so only authenticated users can read/write. Composite indexes will be suggested when you run the app (progress by shop_id, etc.).

---

## 1. Current State

- **SQLite** (`zero_clean.db`): tables `shops`, `variants`, `progress`. No image table; counts come from files on disk.
- **Phone storage:** `ZeroClean_Dataset/{shop}/{category}/{variant}/{context}/` (processed) and `{shop}/Unprocessed/` (new captures). Each image: `.jpg` + sidecar `.json` (ImageRecord).
- **Flow:** Capture → Unprocessed (local). After nudge → move to context folder (local) + update progress in SQLite. After being processed delete from the app private storage 

---

## 2. Design Decisions (Your Changes)

- **Single shop per user** — One shop per user/app; also store **shop coordinates**.
- **Unprocessed stays on device** — New captures live only on app internal storage until the user completes nudge. Upload to Firebase **only after** an image is processed. Processed images are sent to the cloud and not read back (no image viewing from Firebase → minimal egress cost).
- **Validate before “processed”** — When the user taps save, treat as processed only if the associated `.json` has valid/complete data (e.g. annotations, context). Do not rely on the button alone; verify payload before upload and progress update.
- **No existing data** — No migration of old SQLite/files needed.

---

## 3. Target State

**Firestore**

- **shops** — One doc per user/shop: `name`, `locationNote`, **coordinates**, `userId` (if multi-user). Optional: `createdAt`.
- **variants** — Same as now: category, brand, subBrand, volume, material.
- **progress** — Per (variant, shop, context): `currentCount`, `targetCap`. Add **`lastUpdatedAt`** for dashboard “last activity”.
- **images** — One doc per processed image: **`storagePath`** (full Storage path for bulk download), all ImageRecord-like fields (annotations, image_size, device_model, etc.) so export needs no JSON from Storage. Add **`createdAt`**, **`processedAt`**, **`userId`** / **`shopId`** / **`variantId`** / **`context`** for querying and filters.
- **stats** (optional) — One doc per shop (e.g. `stats/{shopId}`) or one global `stats/global`: `totalImages`, `lastUpdatedAt`, per-context counts. Updated when an image is added; lets the dashboard read one doc for real-time totals instead of aggregating many progress docs.

**Firebase Storage**

- **Only processed images** — e.g. `datasets/{userId}/{shopId}/{category}/{variantLabel}/{context}/{imageId}.jpg`. No Unprocessed in Storage; metadata lives in Firestore.

**Local (device)**

- Unprocessed: app internal storage only (image + `.json`). After validated save → upload `.jpg` to Storage, write image doc + update progress in Firestore, then delete local file (or keep briefly for safety). No need to read processed images back from Firebase.

---

## 4. What Changes (Conceptually)

1. **DB** — Replace SQLite with Firestore (shops, variants, progress, images). Single-shop model + coordinates in shop.
2. **Storage** — Upload to Firebase Storage only when an image is **processed** and its `.json` is validated.
3. **Capture** — Still write to local Unprocessed (internal storage). No upload yet.
4. **Nudge/save** — Validate `.json` → if valid: upload image to Storage, create image doc in Firestore, update progress, then remove local file. No listing/reading processed images from cloud.
5. **Permissions** — Can drop broad external storage; use internal storage for Unprocessed and Firebase for processed data. Add Security Rules for Firestore and Storage.

---

## 5. Training Export and Standalone Dashboard

**You downloading all files for training**

- Store **`storagePath`** on every image doc (full path in the Storage bucket). Your export script can query all `images` in Firestore, get `storagePath` (+ metadata), then bulk-download from Storage (e.g. gsutil, Admin SDK). No need to list bucket or read JSON from Storage—Firestore is the manifest.
- Put **full metadata in the image doc** (annotations, image_size, lighting, device_model, etc.) so training pipeline gets labels from Firestore; optional to also write a `.json` next to each image in Storage for backward compatibility.
- **`createdAt` / `processedAt`** — Use for “export since last run”, time-based train/val splits, or filtering by date in the dashboard.
- Keep **Storage path structure** stable and meaningful (e.g. `.../category/variantLabel/context/imageId.jpg`) so downloaded folder tree is ready for training.

**Standalone real-time dashboard**

- Firestore has no server-side SUM/GROUP BY. Use **progress** as the main source: dashboard listens to `progress` docs (e.g. where `shopId == X`) and aggregates in the client. Add **`lastUpdatedAt`** on progress so you can show “last capture” and sort by activity.
- For a single-number total without aggregating many progress docs, maintain **stats** doc(s): e.g. `stats/{shopId}` or `stats/global` with `totalImages`, per-context counts, `lastUpdatedAt`. Update when an image is added (in app or via Cloud Function). Dashboard then subscribes to one or a few stats docs for real-time totals.
- **Indexes** — Create composite indexes for: progress by `shopId`; images by `shopId`, by `processedAt` (for “recent activity”), by `userId` if multi-user. Check Firebase console after first dashboard queries.
- **Multi-user** — If multiple collectors feed the same project, put **`userId`** (and optionally `deviceId`) on shop and image docs so the dashboard can filter by collector or show “all”.

---

## 6. Cost (20,000 images)

- **Storage:** ~40 GB at 2 MB/image → ~**$3.50/month** (5 GB free, then ~$0.10/GB). With compression (~10 GB) → ~**$0.50/month**. No image viewing from cloud keeps egress low.
- **Firestore:** &lt; 1 GiB + normal reads/writes → **$0** at this scale (free tier).
- **Total:** ~**$0.50–4/month** depending on image size. Blaze plan required for Storage.

---

## 7. Risks (Short)

- **Offline:** Queue uploads when network returns; keep Unprocessed on device until successfully uploaded after save.
- **Security:** Firestore and Storage Rules so only your app / authenticated users can write.
- **Validation:** Robust `.json` check before marking processed and uploading to avoid incomplete data in the cloud.

---

## 8. Migration Order

1. Firebase project: Firestore + Storage + (optional) Auth.
2. Firestore schema: single shop + coordinates + userId; variants; progress + lastUpdatedAt; images (storagePath, full metadata, createdAt, processedAt, shopId, variantId, context, userId); optional stats collection.
3. App: Firestore for shops/variants/progress/images; keep Unprocessed on internal storage; on validated save → upload to Storage, write image doc (with storagePath and full metadata), update progress (+ lastUpdatedAt), update stats if used, then remove local file.
4. Define composite indexes for dashboard queries (progress by shopId; images by shopId, processedAt, userId).
5. Remove SQLite and public external storage usage; tighten permissions.

Done: **one shop + coordinates**, **Unprocessed on device**, **upload only when processed and JSON validated**, **no reading images back from Firebase**.

