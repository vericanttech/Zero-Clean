# Zero-Clean · Data lifecycle & Firebase

This document describes **where every kind of data lives** (local vs Firebase), its **lifecycle** (create → read → update → delete), and all **Firebase connections** (Auth, Firestore, Storage), including **sync** and **pull**.

---

## 1. Overview: local vs Firebase

| Layer | Local | Firebase |
|-------|--------|----------|
| **Catalog & progress** | SQLite (`zero_clean_local.db`) — primary read source | Firestore — source of truth when online; synced on Pull/Sync |
| **Image files** | App storage (Unprocessed + Reference cache) | Firebase Storage — processed images only, uploaded on Sync |
| **Image metadata & annotations** | JSON sidecars next to each image | Firestore `images` collection — one doc per processed image (written on Sync, **never read** by app for listing) |
| **Offline queue** | SQLite `pending_sync` table | N/A — pushed to Firestore when user taps Sync |

- **UI always reads from local** (SQLite + filesystem). No live Firestore listeners.
- **Firebase is used** when: user signs in (Auth), user taps **Récupérer** (Pull), user taps **Synchroniser** (Sync), or (legacy path) direct upload after nudge.

---

## 2. Data entities and storage locations

| Data | Local storage | Firebase storage |
|------|----------------|-------------------|
| **Shops** | SQLite `shops` (id, name, location_note, latitude, longitude) | Firestore `shops` (same fields + `userId`, `createdAt`) |
| **Variants** | SQLite `variants` (id, shop_id, category, brand, sub_brand, volume, material) | Firestore `shops/{shopId}/variants` subcollection (same fields, no id in body; doc id = variant id) |
| **Progress** | SQLite `progress` (variant_id, shop_id, context, current_count, target_cap, last_updated_at) | Firestore `progress` collection (same; composite query by variant_id, shop_id, context) |
| **Pending sync** | SQLite `pending_sync` (id, kind, payload, created_at) | N/A — queue only; applied to Firestore on Sync |
| **Unprocessed images** | Filesystem: `ZeroClean_Unprocessed/{shopName}/Unprocessed/*.jpg` + `*.json` | None |
| **Processed images (files)** | Reference cache: `ZeroClean_Reference/*.jpg` (72h retention, 2 GB cap) | Firebase Storage: `datasets/{userId}/{shopId}/{category}/{variantLabel}/{context}/{imageId}.jpg` |
| **Processed image metadata** | Same as above: `ZeroClean_Reference/*.json` | Firestore `images` collection (one doc per image; `storage_path`, `user_id`, `shop_id`, `variant_id`, `context`, `created_at`, etc.) |
| **Annotations** | Only in JSON sidecars (per-image); not in SQLite | In Firestore `images` doc as part of `fullMetadata` |
| **Auth / user** | SharedPreferences: `zero_clean_current_shop_id`, `zero_clean_current_user_id` | Firebase Auth (email/password); no user doc in Firestore |

---

## 3. Lifecycle of each data type

### 3.1 Shops

| Phase | What happens |
|-------|-------------------------------|
| **Create** | **Pull:** Firestore `getShops()` → if empty, `ensureShopForCurrentUser()` (creates one with `name = uid`) → `saveAllFromRemote()` writes to SQLite. **Admin path:** `addShop()` → `getOrCreateUserShop()` → Firestore + `local.insertShop()`. |
| **Read** | App always uses `LocalDbService.getShops()` (from SQLite). Firestore is only read during Pull or `ensureShopForCurrentUser()`. |
| **Update** | **Local:** `updateShopProfile()` → `LocalDbService.updateShop()` + `SyncService.queueShopProfile()`. **Firebase:** When user taps Sync, `_applyPending('shop_profile')` → `FirestoreService.updateShop()`. |
| **Delete** | Not implemented (no delete shop in app). |

### 3.2 Variants

| Phase | What happens |
|-------|-------------------------------|
| **Create** | User adds variant in Setup → `AppState.addVariant()` → `LocalDbService.insertVariant()` (id = Firestore doc id or `local_{timestamp}`) + `ensureProgressRow()` for each context + `SyncService.queueVariant()`. |
| **Read** | App uses `LocalDbService.getVariants(shopId)` / `getCategories(shopId)`. Firestore variants are only read during Pull. |
| **Update** | Not implemented (no edit variant in app). |
| **Delete** | Not implemented. |
| **Sync** | On Sync, `_applyPending('variant')` → `FirestoreService.setVariantWithId()` + `ensureProgressRow()` in Firestore and local; pending_sync row removed. |

### 3.3 Progress (counts per variant/shop/context)

| Phase | What happens |
|-------|-------------------------------|
| **Create** | When variant is added: `ensureProgressRow()` in local (and on Sync in Firestore). When image is processed: `recordCaptureFor()` → `LocalDbService.incrementProgressCount()`; on Sync for `processed_image`, Firestore `incrementCount()` / `ensureProgressRow()` per variant in annotations. |
| **Read** | `LocalDbService.getProgressForShop(shopId)` and `getTotalStats()`. Firestore progress is only read during Pull. |
| **Update** | Local: `incrementProgressCount()`. Firestore: `incrementCount()` during Sync when applying `processed_image` pending item. |
| **Delete** | Implicit when Pull replaces all local progress in `saveAllFromRemote()`. |

### 3.4 Pending sync queue

| Phase | What happens |
|-------|-------------------------------|
| **Create** | `queueShopProfile()`, `queueVariant()`, `queueProcessedImage()` → `LocalDbService.addPendingSync(kind, payload)`. |
| **Read** | `LocalDbService.getPendingSync()` during Sync; `getPendingVariantIds()` for UI (e.g. “sync first” hint). |
| **Update** | N/A. |
| **Delete** | `removePendingSync(id)` after successful `_applyPending()` for that item. |

### 3.5 Unprocessed images (capture → nudge)

| Phase | What happens |
|-------|-------------------------------|
| **Create** | **Capture:** `CaptureScreen._capture()` → `FileSystemService.captureToUnprocessed()`: writes `.jpg` + `.json` under `ZeroClean_Unprocessed/{shopName}/Unprocessed/`. JSON contains `shop_name`, `category`, `variant_label`, `annotations`, `metadata`, `shop_context: 'unprocessed'`. No DB or Firebase write. |
| **Read** | **Review:** `ReviewScreen._load()` when filter = unprocessed → `getUnprocessedPath()` → list `.jpg` in that dir, load sidecar JSON. |
| **Update** | **Nudge:** User edits boxes/labels in BBoxNudgeScreen; Save writes JSON back to same sidecar (and optionally runs process flow below). |
| **Delete** | When user saves from nudge with valid annotations and context: file is **moved** to reference cache (no longer in Unprocessed). |

### 3.6 Processed images (after nudge Save)

| Phase | What happens |
|-------|-------------------------------|
| **Create (local)** | **Nudge Save (unprocessed):** `FileSystemService.processLocallyOnly()`: validates JSON, moves `.jpg` and writes `.json` to `ZeroClean_Reference/`, strips `shop_name`/`category`/`variant_label` from stored JSON, returns payload. Then `AppState.recordCaptureFor()` (local progress), `SyncService.queueProcessedImage(payload)`, `refreshProgress()`. |
| **Create (Firebase)** | When user taps **Synchroniser**, `_applyPending('processed_image')` runs for each queued item: `FirebaseStorageService.uploadProcessedImage()` → path `datasets/{userId}/{shopId}/{category}/{variantLabel}/{context}/{imageId}.jpg`; then `FirestoreService.addImageDoc()` (images collection), `incrementCount()` and `ensureProgressRow()` for each variant in annotations, `incrementStatsTotal(shopId)`. Pending row removed. |
| **Read** | **Review:** When filter = single/shelf/checkout, `FileSystemService.listReferenceCacheImages(shopContext)` lists reference cache only (local). App **does not** list images from Firestore or Storage. |
| **Update** | Edits in BBoxNudgeScreen for an already-processed (reference cache) image only update local JSON; no re-upload. |
| **Delete** | Reference cache: `runRetentionCleanup()` deletes files older than 72h or when total size > 2 GB. Firebase: no delete implemented. |

### 3.7 Annotations (bounding boxes + labels)

| Phase | What happens |
|-------|-------------------------------|
| **Storage** | Only in JSON sidecars (and inside Firestore `images` doc as part of metadata when uploaded). Never in SQLite. |
| **Create/Update** | BBoxNudgeScreen: user draws/edits boxes → Save → `FileSystemService.updateAnnotations()` or full JSON write. For unprocessed save, also `processLocallyOnly()` and queue. |
| **Read** | From JSON when opening nudge or review (filesystem only). |

---

## 4. Firebase connections

### 4.1 Firebase Auth

| Connection | Where | Purpose |
|------------|--------|---------|
| **Initialize** | `main.dart`: `Firebase.initializeApp()` | Required before any Firebase API. |
| **Auth state** | `main.dart`: `StreamBuilder<User?>(stream: FirebaseAuth.instance.authStateChanges())` | Switches between `LoginScreen` and main app. |
| **Sign in** | `login_screen.dart`: `FirebaseAuth.instance.signInWithEmailAndPassword()` | Email/password login; no sign-up in app. |
| **Sign out** | `no_shop_screen.dart` (and Setup): `FirebaseAuth.instance.signOut()` | Clears user; app clears local DB and shows login. |
| **Current user** | `FirestoreService`, `SyncService`, `AppState`, `BBoxNudgeScreen`: `FirebaseAuth.instance.currentUser?.uid` | Used for Firestore/Storage paths and ensuring shop. |

- No Firestore “users” collection; identity is Auth UID only.
- On init, if `currentUser == null`, app clears local DB and persisted shop/user id.

### 4.2 Firestore

| Collection / path | Read by app | Written by app |
|-------------------|-------------|----------------|
| **`shops`** | Pull: `getShops()` (where `userId == uid`); `ensureShopForCurrentUser()` / `getOrCreateUserShop()` | `insertShop()`, `updateShop()`, `getOrCreateUserShop()` |
| **`shops/{shopId}/variants`** | Pull: `getVariants(shopId)`, `getVariantsByCategory()`, `getCategories()` | `setVariantWithId()`, `insertVariant()` |
| **`progress`** | Pull: `getProgressForShop(shopId)`, `getProgress()`, `getTotalStats()` | `incrementCount()`, `ensureProgressRow()` |
| **`images`** | **Never** (app does not list images from Firestore) | `addImageDoc()` when applying `processed_image` pending item |
| **`stats`** | Not read by app | `incrementStatsTotal(shopId)` when applying `processed_image` |

- All Firestore writes from the app go through `FirestoreService` (and for images/progress, via `SyncService._applyPending`).
- Pull replaces local catalog and progress in one transaction (`saveAllFromRemote()`); it does not merge.

### 4.3 Firebase Storage

| Connection | Where | Purpose |
|------------|--------|---------|
| **Upload** | `FirebaseStorageService.uploadProcessedImage()` | Called from `SyncService._applyPending('processed_image')`. Path: `datasets/{userId}/{shopId}/{category}/{variantLabel}/{context}/{imageId}.jpg`. |
| **Download / list** | Not used | App never downloads or lists from Storage; images are only uploaded. |

---

## 5. Sync and pull flows

### 5.1 Pull (Récupérer) — Firestore → SQLite only

**When:** User taps **Récupérer** on Setup. Allowed only when **there is no local data** (`shops.isEmpty`).

**Steps:**

1. `AppState.pullNow()`:
   - If `shops.isNotEmpty`, return (button disabled in UI).
   - `FirestoreService.getShops()`.
   - If empty, `FirestoreService.ensureShopForCurrentUser()` (creates shop with `name = uid`), then `getShops()` again.
   - If still empty, set `loadError` and return.
   - `SyncService.pullFromRemote()` → `_pullFromFirestore()`:
     - `getShops()` from Firestore.
     - For each shop: `getVariants(shopId)`, `getProgressForShop(shopId)`.
     - `LocalDbService.saveAllFromRemote(shops, variantsByShop, progressByShop)`:
       - One transaction: delete all local `progress`, `variants`, `shops`; insert all from Firestore.
   - Persist current shop id and user id in SharedPreferences.
   - `_loadFromLocal()` to refresh UI.

**Result:** Local SQLite is a full copy of Firestore shops/variants/progress. No pending_sync or image upload.

### 5.2 Sync (Synchroniser) — Push pending queue to Firebase

**When:** User taps **Synchroniser** on Setup (or equivalent). No pull; only push.

**Steps:**

1. `AppState.syncNow()`:
   - `SyncService.pushPendingOnly()` → `_pushPendingToFirestore()`:
     - `LocalDbService.getPendingSync()` (ordered by id).
     - For each item, `_applyPending(item)`:
       - **`variant`:** `FirestoreService.setVariantWithId()`, then `ensureProgressRow()` for each context (Firestore + local); `removePendingSync(id)`.
       - **`shop_profile`:** `FirestoreService.updateShop(shopId, ...)`; `removePendingSync(id)`.
       - **`processed_image`:** Build file from `ref_image_path`; `FirebaseStorageService.uploadProcessedImage()`; `FirestoreService.addImageDoc()`; `ensureProgressRow()` + `incrementCount()` for each variant in annotations; `incrementStatsTotal(shopId)`; `removePendingSync(id)`. On file missing, skip and leave in queue.
     - On failure for an item, leave in queue (no remove).
   - `_loadFromLocal()` and refresh `_pendingVariantIds`.

**Result:** Pending variants, shop profile updates, and processed images are written to Firestore (and Storage for images). Local progress was already updated when user saved in nudge; Firestore progress is updated during this push.

### 5.3 Full sync (pull then push)

**When:** Not exposed in UI. Internally `SyncService.syncFromRemote()` does:

1. `_pullFromFirestore()` (same as Pull).
2. `_pushPendingToFirestore()` (same as Sync).

So: first overwrite local with Firestore, then push any pending local changes. The app currently uses **pull** and **sync** as separate actions.

---

## 6. UI triggers summary

| Action | Effect |
|--------|--------|
| **Login** | Auth state → main app; `AppState.init()` loads from SQLite only; if different user or shop id mismatch, local cleared and reloaded. |
| **Récupérer (Setup)** | Pull: Firestore → SQLite (only if `shops.isEmpty`). |
| **Synchroniser (Setup)** | Push: `pending_sync` → Firestore (and Storage for processed images). |
| **Add variant (Setup)** | Local insert + progress rows + queue variant for Sync. |
| **Update shop profile (Setup)** | Local update + queue shop_profile for Sync. |
| **Capture photo** | Write image + JSON to Unprocessed folder only. |
| **Save in Nudge (unprocessed)** | `processLocallyOnly()` → move to reference cache, update local progress, `queueProcessedImage()`. |
| **Sign out** | Clear local DB and persisted ids; Auth sign out. |

---

## 7. Summary table: where each piece of data is created, read, and synced

| Data | Created (local) | Created (Firebase) | Read from | Pushed to Firebase |
|------|----------------|--------------------|-----------|--------------------|
| Shops | Pull / addShop | ensureShop / insertShop / updateShop | SQLite | Sync (shop_profile) |
| Variants | addVariant / Pull | setVariantWithId / insertVariant | SQLite | Sync (variant) |
| Progress | addVariant, recordCaptureFor, Pull | ensureProgressRow, incrementCount | SQLite | Sync (variant + processed_image) |
| Pending sync | queue* | — | SQLite | Consumed by Sync |
| Unprocessed images | captureToUnprocessed | — | Filesystem | — |
| Processed images (file) | processLocallyOnly (move to cache) | uploadProcessedImage on Sync | Reference cache | Sync (processed_image) |
| Processed image doc | — | addImageDoc on Sync | Never | Sync (processed_image) |
| Annotations | BBox nudge Save | Inside image doc metadata | JSON sidecars | With processed_image |

This completes the data lifecycle and Firebase connection picture for Zero-Clean.
