// ─────────────────────────────────────────────
//  ZERO-CLEAN  ·  Core Data Models
// ─────────────────────────────────────────────

import 'dart:ui'; // or import 'package:flutter/material.dart';

class Shop {
  final String? id;
  final String name;
  final String locationNote;
  final double? latitude;
  final double? longitude;

  Shop({
    this.id,
    required this.name,
    this.locationNote = '',
    this.latitude,
    this.longitude,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'location_note': locationNote,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
      };

  factory Shop.fromMap(Map<String, dynamic> m) => Shop(
        id: m['id']?.toString(),
        name: m['name'] as String? ?? '',
        locationNote: m['location_note'] as String? ?? '',
        latitude: (m['latitude'] as num?)?.toDouble(),
        longitude: (m['longitude'] as num?)?.toDouble(),
      );
}

class Variant {
  final String? id;
  final String category;
  final String brand;
  final String subBrand;
  final String volume;
  final String material;

  Variant({
    this.id,
    required this.category,
    required this.brand,
    required this.subBrand,
    required this.volume,
    required this.material,
  });

  /// e.g. "Coke_Zero_330ml_CAN" or "Coke_500ml_PET" when no sub-brand (single underscore).
  String get fullLabel {
    final parts = subBrand.trim().isEmpty
        ? [brand, volume, material]
        : [brand, subBrand, volume, material];
    final joined = parts.join('_').replaceAll(' ', '_');
    return joined.replaceAll(RegExp(r'_+'), '_');
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'category': category,
        'brand': brand,
        'sub_brand': subBrand,
        'volume': volume,
        'material': material,
      };

  factory Variant.fromMap(Map<String, dynamic> m) => Variant(
        id: m['id']?.toString(),
        category: m['category'] as String? ?? '',
        brand: m['brand'] as String? ?? '',
        subBrand: m['sub_brand'] as String? ?? '',
        volume: m['volume'] as String? ?? '',
        material: m['material'] as String? ?? '',
      );
}

enum CaptureContext { single, shelf, checkout }

extension CaptureContextExt on CaptureContext {
  String get name {
    switch (this) {
      case CaptureContext.single:
        return 'single';
      case CaptureContext.shelf:
        return 'shelf';
      case CaptureContext.checkout:
        return 'checkout';
    }
  }

  int get targetCap {
    switch (this) {
      case CaptureContext.single:
        return 65; // midpoint of 50–80
      case CaptureContext.shelf:
        return 25;
      case CaptureContext.checkout:
        return 25;
    }
  }

  /// French label for UI (dashboard, etc.)
  String get labelFr {
    switch (this) {
      case CaptureContext.single:
        return 'Unité';
      case CaptureContext.shelf:
        return 'Rayon';
      case CaptureContext.checkout:
        return 'Caisse';
    }
  }
}

class Progress {
  final String? id;
  final String variantId;
  final String shopId;
  final CaptureContext context;
  int currentCount;
  final int targetCap;
  final DateTime? lastUpdatedAt;

  Progress({
    this.id,
    required this.variantId,
    required this.shopId,
    required this.context,
    this.currentCount = 0,
    required this.targetCap,
    this.lastUpdatedAt,
  });

  double get pct => (currentCount / targetCap).clamp(0.0, 2.0);

  ProgressStatus get status {
    if (pct < 0.30) return ProgressStatus.critical;
    if (pct < 1.00) return ProgressStatus.building;
    return ProgressStatus.saturated;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'variant_id': variantId,
        'shop_id': shopId,
        'context': context.name,
        'current_count': currentCount,
        'target_cap': targetCap,
        if (lastUpdatedAt != null) 'last_updated_at': lastUpdatedAt!.toIso8601String(),
      };

  factory Progress.fromMap(Map<String, dynamic> m) {
    final ctx = CaptureContext.values.firstWhere(
      (e) => e.name == m['context'],
      orElse: () => CaptureContext.single,
    );
    final lastAt = m['last_updated_at'];
    return Progress(
      id: m['id']?.toString(),
      variantId: m['variant_id']?.toString() ?? '',
      shopId: m['shop_id']?.toString() ?? '',
      context: ctx,
      currentCount: (m['current_count'] as num?)?.toInt() ?? 0,
      targetCap: (m['target_cap'] as num?)?.toInt() ?? ctx.targetCap,
      lastUpdatedAt: lastAt != null ? DateTime.tryParse(lastAt.toString()) : null,
    );
  }
}

enum ProgressStatus { critical, building, saturated }

class BBox {
  double x, y, w, h; // normalized [0,1]: x=left, y=top, w=width, h=height

  BBox(this.x, this.y, this.w, this.h);

  factory BBox.fromList(List<dynamic> l) =>
      BBox(l[0].toDouble(), l[1].toDouble(), l[2].toDouble(), l[3].toDouble());

  List<double> toList() => [x, y, w, h];

  /// Clamp all values to valid normalized range
  void clamp() {
    x = x.clamp(0.0, 1.0);
    y = y.clamp(0.0, 1.0);
    w = w.clamp(0.01, 1.0 - x);
    h = h.clamp(0.01, 1.0 - y);
  }

  BBox copy() => BBox(x, y, w, h);

  /// Convert from pixel rect on a canvas of [canvasW] x [canvasH]
  factory BBox.fromPixelRect(Rect r, double canvasW, double canvasH) {
    final left = r.left.clamp(0.0, canvasW);
    final top = r.top.clamp(0.0, canvasH);
    final right = r.right.clamp(0.0, canvasW);
    final bottom = r.bottom.clamp(0.0, canvasH);
    return BBox(
      left / canvasW,
      top / canvasH,
      (right - left) / canvasW,
      (bottom - top) / canvasH,
    );
  }

  /// Convert to pixel rect on a canvas of [canvasW] x [canvasH]
  Rect toPixelRect(double canvasW, double canvasH) => Rect.fromLTWH(
        x * canvasW,
        y * canvasH,
        w * canvasW,
        h * canvasH,
      );

  /// Convert to pixel rect inside the [fitted] rect (BoxFit.contain image area).
  /// Use this when the image is displayed with letterbox/pillarbox so coords
  /// stay in image space (0–1) and match the actual image file.
  Rect toPixelRectInFitted(Rect fitted) => Rect.fromLTWH(
        fitted.left + x * fitted.width,
        fitted.top + y * fitted.height,
        w * fitted.width,
        h * fitted.height,
      );

  @override
  String toString() =>
      'BBox(x:${x.toStringAsFixed(3)}, y:${y.toStringAsFixed(3)}, '
      'w:${w.toStringAsFixed(3)}, h:${h.toStringAsFixed(3)})';
}

/// Annotation: ID-based (variant_id + box). fullLabel optional for display / legacy JSON.
class Annotation {
  /// Variant document id (required for new ID-based JSON).
  final String? variantId;
  /// Human-readable label (from Variant.fullLabel); used for display and when reading legacy JSON).
  final String? fullLabel;
  // Legacy fields (only set when reading old JSON without variant_id).
  final String brand;
  final String subBrand;
  final String volume;
  final String material;
  BBox bbox;
  bool verified;

  Annotation({
    this.variantId,
    this.fullLabel,
    this.brand = '',
    this.subBrand = '',
    this.volume = '',
    this.material = '',
    required this.bbox,
    this.verified = false,
  });

  /// Display label: fullLabel if set, else build from brand/subBrand/volume/material for legacy.
  String get displayLabel =>
      fullLabel ?? '${brand}_${subBrand}_${volume}_$material'.replaceAll(' ', '_');

  factory Annotation.fromMap(Map<String, dynamic> m) => Annotation(
        variantId: m['variant_id']?.toString() ?? m['variantId']?.toString(),
        fullLabel: m['full_label'] as String?,
        brand: m['brand'] as String? ?? '',
        subBrand: m['sub_brand'] as String? ?? '',
        volume: m['volume'] as String? ?? '',
        material: m['material'] as String? ?? '',
        bbox: BBox.fromList((m['bbox'] as List?) ?? [0.1, 0.1, 0.8, 0.8]),
        verified: m['verified'] as bool? ?? false,
      );

  Annotation copyWith({BBox? bbox, bool? verified, String? variantId, String? fullLabel}) => Annotation(
        variantId: variantId ?? this.variantId,
        fullLabel: fullLabel ?? this.fullLabel,
        brand: brand,
        subBrand: subBrand,
        volume: volume,
        material: material,
        bbox: bbox ?? this.bbox.copy(),
        verified: verified ?? this.verified,
      );

  /// For ID-based JSON sidecars: only variant_id, bbox, verified.
  Map<String, dynamic> toMapIdBased() => {
        'variant_id': variantId ?? '',
        'bbox': bbox.toList(),
        'verified': verified,
      };

  /// Legacy toMap (full label fields); prefer toMapIdBased() for new JSON.
  Map<String, dynamic> toMap() => {
        if (variantId != null) 'variant_id': variantId,
        'brand': brand,
        'sub_brand': subBrand,
        'volume': volume,
        'material': material,
        if (fullLabel != null) 'full_label': fullLabel,
        'bbox_mode': 'normalized_0_1',
        'bbox': bbox.toList(),
        'verified': verified,
      };
}

/// ImageRecord: ID-based sidecar. shop_id + context only; no shop_name/category/variant_label.
class ImageRecord {
  final String imageId;
  final String shopId;
  /// single | shelf | checkout | unprocessed
  final String context;
  final int width;
  final int height;
  final List<Annotation> annotations;
  final String lighting;
  final String angle;
  final bool isEdgeCase;
  final String? edgeType;
  final String condition;
  final String occlusion;
  final String? deviceModel;

  ImageRecord({
    required this.imageId,
    required this.shopId,
    required this.context,
    required this.width,
    required this.height,
    required this.annotations,
    this.lighting = 'natural',
    this.angle = 'front',
    this.isEdgeCase = false,
    this.edgeType,
    this.condition = 'good',
    this.occlusion = 'none',
    this.deviceModel,
  });

  Map<String, dynamic> toJson() => {
        'image_id': imageId,
        'shop_id': shopId,
        'context': context,
        'image_size': {'width': width, 'height': height},
        'annotations': annotations.map((a) => a.toMapIdBased()).toList(),
        'metadata': {
          'lighting': lighting,
          'angle': angle,
          'is_edge_case': isEdgeCase,
          if (edgeType != null) 'edge_type': edgeType,
          'condition': condition,
          'occlusion': occlusion,
          if (deviceModel != null) 'device_model': deviceModel,
        },
      };
}
