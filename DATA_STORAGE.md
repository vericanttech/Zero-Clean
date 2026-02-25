# Zero-Clean · Data storage

This document describes what data lives in the **SQLite database** (`.db`) and in the **JSON sidecar files** (`.json`) next to images, so you know what goes where.

---

## 1. SQLite database (`zero_clean.db`)

**Location:** app database path (e.g. `getDatabasesPath()` / `zero_clean.db`).

The app uses a single SQLite file. It holds **configuration and progress**: shops, product variants, and per-shop/per-variant capture progress. It does **not** store image paths or annotations; those live in the filesystem and in JSON files.

### Table: `shops`

| Column          | Type    | Description                          |
|-----------------|---------|--------------------------------------|
| `id`            | INTEGER | Primary key (auto)                   |
| `name`          | TEXT    | Shop name (e.g. `Boutique_Moussa`)   |
| `location_note` | TEXT    | Optional note (e.g. `Dakar Centre`)  |

- **Stored here:** List of shops (stores) where you capture.
- **Used for:** Choosing shop when capturing, progress per shop, moving files into shop/category/variant folders.

---

### Table: `variants`

| Column      | Type    | Description                                      |
|-------------|---------|--------------------------------------------------|
| `id`        | INTEGER | Primary key (auto)                               |
| `category`  | TEXT    | Category (e.g. `Boissons`, `Fruits`, `Légumes`)  |
| `brand`     | TEXT    | Brand (e.g. `Coke`, `Pomme`)                     |
| `sub_brand` | TEXT    | Sub-brand (e.g. `Zero`; can be empty)            |
| `volume`    | TEXT    | Volume (e.g. `500ml`, `Unité`)                   |
| `material`  | TEXT    | Material (e.g. `PET`, `CAN`, `PRODUCE`)          |

- **Stored here:** Product variants. Display label is built as `brand_subBrand_volume_material` (e.g. `Coke_Zero_500ml_PET`, `Pomme__Unité_PRODUCE`).
- **Used for:** Picking product when capturing, folder structure (shop/category/variant), and as **class names for training** (the full label is the class).

---

### Table: `progress`

| Column        | Type    | Description                                      |
|---------------|---------|--------------------------------------------------|
| `id`          | INTEGER | Primary key (auto)                               |
| `variant_id`  | INTEGER | FK → `variants(id)`                              |
| `shop_id`     | INTEGER | FK → `shops(id)`                                 |
| `context`     | TEXT    | `single` \| `shelf` \| `checkout`                 |
| `current_count` | INTEGER | Number of images captured for this combo        |
| `target_cap`  | INTEGER | Target images per variant/shop/context (e.g. 65)  |

- **Unique:** `(variant_id, shop_id, context)`.
- **Stored here:** How many images you’ve captured per variant, per shop, per context (single/shelf/checkout).
- **Used for:** Dashboard progress, “cap” for data collection.

---

## 2. JSON files (per-image sidecars)

**Location:** Next to each image. For an image `IMG_123.jpg`, the sidecar is `IMG_123.json` in the same directory.

**Stored here:** Everything that describes **that image**: bounding boxes, labels, and capture metadata. Used for training and for the Nudge/Review flows.

The app **reads and writes** these JSON files; the **database never stores annotations or image paths**.

---

### 2.1 Top-level keys

| Key             | Type   | Always present | Description |
|-----------------|--------|----------------|-------------|
| `annotations`   | array  | yes            | List of annotation objects (see below). |
| `metadata`      | object | yes            | Capture conditions (lighting, angle, etc.). |
| `shop_context`  | string | yes            | `single` \| `shelf` \| `checkout`. |
| `image_id`      | string | no*            | Identifier for the image (e.g. filename or UUID). |
| `image_size`    | object | no*            | `{ "width": number, "height": number }`. |
| `shop_name`     | string | no**           | Only in **unprocessed** JSON; removed when moved to context folder. |
| `category`      | string | no**           | Only in **unprocessed** JSON; removed when moved. |
| `variant_label` | string | no**           | Only in **unprocessed** JSON; removed when moved. |

\* Often set when the JSON is first created (e.g. at capture); may be missing on older or nudge-only saves.  
\** Present only in the “unprocessed” capture folder; stripped when the file is moved to the final context folder (e.g. after Nudge → Save).

---

### 2.2 `metadata` object

| Key            | Type   | Example / notes |
|----------------|--------|------------------|
| `lighting`     | string | `natural`, `dim_yellow`, `bright_white`, `neon` |
| `angle`        | string | `front`, `top_down`, `angled_45`, `side` |
| `is_edge_case` | bool   | `true` / `false` |
| `edge_type`    | string | Optional; only if `is_edge_case` is true. |
| `condition`    | string | `good`, `damaged`, `faded`, `counterfeit` |
| `occlusion`    | string | `none`, `partial`, `heavy` |

---

### 2.3 `annotations` array – one object per bounding box

Each element is an **annotation** (one product box in the image):

| Key          | Type    | Description |
|--------------|---------|-------------|
| `brand`      | string  | Brand (e.g. `Coke`, `Pomme`). |
| `sub_brand`  | string  | Sub-brand (can be `""`). |
| `volume`     | string  | e.g. `500ml`, `Unité`. |
| `material`   | string  | e.g. `PET`, `PRODUCE`. |
| `full_label` | string  | Full class name (e.g. `Coke_Zero_500ml_PET`). Used for training. |
| `bbox_mode`  | string  | Always `normalized_0_1` in this app. |
| `bbox`       | array   | `[x, y, w, h]` normalized 0–1 (left, top, width, height). |
| `verified`   | bool    | Whether this box was verified (e.g. post-nudge). |

- **Stored in JSON only:** Annotations are **not** stored in the database; they live only in the `.json` next to each image.
- **Training:** Export/training pipelines use `full_label` as the class and `bbox` (and image size) for the box.

---

## 3. Quick reference: what goes where

| Data                         | Stored in   | Notes |
|-----------------------------|------------|--------|
| Shops (name, location note) | **.db**    | `shops` table. |
| Product variants (category, brand, volume, material, full label) | **.db** | `variants` table. |
| Progress (count per variant/shop/context) | **.db** | `progress` table. |
| Annotations (boxes + labels per image) | **.json** | `annotations` array in image sidecar. |
| Capture metadata (lighting, angle, condition, etc.) | **.json** | `metadata` in image sidecar. |
| Shop context (single/shelf/checkout) | **.json** | `shop_context` in image sidecar. |
| Image path / file location  | **Filesystem** | Not in DB or JSON; folder structure = shop/category/variant/context. |

---

## 4. Example JSON (minimal, after nudge)

```json
{
  "annotations": [
    {
      "brand": "Pomme",
      "sub_brand": "",
      "volume": "Unité",
      "material": "PRODUCE",
      "full_label": "Pomme__Unité_PRODUCE",
      "bbox_mode": "normalized_0_1",
      "bbox": [0.12, 0.25, 0.35, 0.5],
      "verified": false
    }
  ],
  "metadata": {
    "lighting": "natural",
    "angle": "front",
    "is_edge_case": false,
    "condition": "good",
    "occlusion": "none"
  },
  "shop_context": "single"
}
```

This is the shape you get when saving from the Nudge screen. Unprocessed captures may also include `image_id`, `image_size`, `shop_name`, `category`, and `variant_label` until the file is moved to the context folder.
