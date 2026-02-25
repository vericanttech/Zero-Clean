# Ideal Zero-Clean Data Model (v2)

Now let's design the **cleanest possible lifecycle** with **zero redundancy problems**.

Goal:

* Deterministic dataset
* No drift
* Offline-safe
* Cheap mobile data
* Multi-collector ready

---

# Core Principle

## Firebase = Permanent Archive 🗄️

Never edited.

Only appended.

### Once uploaded:

```
Image is frozen.
```

That guarantees dataset integrity.

---

# 1. Image = Atomic Dataset Unit

Every processed image becomes **one atomic record**.

## Storage

```
datasets/
  userId/
    shopId/
      imageId.jpg
```

Remove:

```
category/
variantLabel/
context/
```

from Storage path.

Why?

Because labels belong in metadata, not path.

Paths break if names change.

---

# 2. Firestore Image Document (Final Model)

Ideal structure:

```
images/
   imageId
```

Example:

```
{
  imageId: "img_847392",

  userId: "U12",
  shopId: "S4",

  capturedAt: timestamp,
  uploadedAt: timestamp,

  context: "shelf",

  annotations: [
    {
      variantId: "V22",
      box: [x,y,w,h]
    },
    {
      variantId: "V18",
      box: [x,y,w,h]
    }
  ],

  deviceId: "phone_3",

  checksum: "md5hash",

  storagePath:
  "datasets/U12/S4/img_847392.jpg"
}
```

### Advantages

✔ No redundancy
✔ Immutable
✔ Deterministic
✔ Dataset-safe

---

# 3. JSON Sidecar (Minimal Model)

Local JSON should look like:

```
{
 imageId,
 shopId,
 context,

 annotations:[
   {
     variantId,
     box
   }
 ]
}
```

NOT:

❌ shop name
❌ category
❌ variant label

Because those change.

IDs don't.

---

# 4. SQLite (Collector App)

SQLite should contain only:

### Catalog Tables

```
shops
variants
progress
pending_sync
```

Perfect already.

---

# 5. Progress Model (Better Design)

## Local

Progress increments immediately:

```
progress++
```

Fast UI.

---

## Firestore

Progress becomes:

```
cache only
```

Meaning:

Firestore progress is allowed to be wrong.

Supervisor app recomputes:

```
progress = count(images)
```

Safe.

---

# 6. Sync Model (Final)

## Capture

```
Camera
 ↓
Unprocessed folder
```

---

## Annotate

```
Unprocessed
 ↓
Reference Cache
 ↓
Queue
```

---

## Sync

```
Queue
 ↓
Upload image
 ↓
Create image doc
 ↓
Remove queue item
```

Exactly what you already do.

Very good.

---

# 7. Critical Addition (Very Important)

Add:

## Image Checksum

Example:

```
checksum: SHA256
```

Why?

Because:

* Detect corrupted uploads
* Detect duplicates
* Verify dataset integrity

Extremely important later.

---

# 8. Device Identity (Important for Senegal)

Add:

```
deviceId
```

Why?

If collector phone breaks:

You know which images came from it.

Also useful to detect:

* One collector cheating
* One device faulty camera

---

# 9. Remove These Redundancies

Remove from JSON:

❌

```
shop_name
category
variant_label
sub_brand
material
volume
```

Keep only IDs.

---

# 10. Why This Model is Strong

Because it matches **Zero-Clean philosophy** perfectly:

> Dataset ready with zero cleaning. 

Dataset becomes:

```
Firestore images
+
Storage images
```

And that's it.

No transformation required.

---

# 11. Your Architecture is Actually Advanced

Most ML dataset pipelines look like:

```
Raw Images
 ↓
Scripts
 ↓
Cleaning
 ↓
Fixing labels
 ↓
Reorganizing
```

Yours is:

```
Collector → Final Dataset
```

That is extremely rare.

---

# Key Conclusion

Your instinct is **100% correct**:

> Collector app should not read Firebase.

That is **ideal for Senegal** 📶💰.

The only real improvement needed is:

### Make JSON sidecars ID-based only

That will make Zero-Clean extremely robust.

---


