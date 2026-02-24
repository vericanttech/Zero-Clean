// ─────────────────────────────────────────────
//  ZERO-CLEAN  ·  Core Data Models
// ─────────────────────────────────────────────

import 'dart:ui'; // or import 'package:flutter/material.dart';

class Shop {
  final int? id;
  final String name;
  final String locationNote;

  Shop({this.id, required this.name, this.locationNote = ''});

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'location_note': locationNote,
      };

  factory Shop.fromMap(Map<String, dynamic> m) => Shop(
        id: m['id'],
        name: m['name'],
        locationNote: m['location_note'] ?? '',
      );
}

class Variant {
  final int? id;
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

  /// e.g. "Coke_Zero_330ml_CAN"
  String get fullLabel =>
      '${brand}_${subBrand}_${volume}_$material'.replaceAll(' ', '_');

  Map<String, dynamic> toMap() => {
        'id': id,
        'category': category,
        'brand': brand,
        'sub_brand': subBrand,
        'volume': volume,
        'material': material,
      };

  factory Variant.fromMap(Map<String, dynamic> m) => Variant(
        id: m['id'],
        category: m['category'],
        brand: m['brand'],
        subBrand: m['sub_brand'],
        volume: m['volume'],
        material: m['material'],
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
  final int? id;
  final int variantId;
  final int shopId;
  final CaptureContext context;
  int currentCount;
  final int targetCap;

  Progress({
    this.id,
    required this.variantId,
    required this.shopId,
    required this.context,
    this.currentCount = 0,
    required this.targetCap,
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
      };

  factory Progress.fromMap(Map<String, dynamic> m) {
    final ctx = CaptureContext.values.firstWhere(
      (e) => e.name == m['context'],
      orElse: () => CaptureContext.single,
    );
    return Progress(
      id: m['id'],
      variantId: m['variant_id'],
      shopId: m['shop_id'],
      context: ctx,
      currentCount: m['current_count'] ?? 0,
      targetCap: m['target_cap'] ?? ctx.targetCap,
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

class Annotation {
  final String brand;
  final String subBrand;
  final String volume;
  final String material;
  final String fullLabel;
  BBox bbox;
  bool verified;

  Annotation({
    required this.brand,
    required this.subBrand,
    required this.volume,
    required this.material,
    required this.fullLabel,
    required this.bbox,
    this.verified = false,
  });

  factory Annotation.fromMap(Map<String, dynamic> m) => Annotation(
        brand: m['brand'] ?? '',
        subBrand: m['sub_brand'] ?? '',
        volume: m['volume'] ?? '',
        material: m['material'] ?? '',
        fullLabel: m['full_label'] ?? '',
        bbox: BBox.fromList((m['bbox'] as List?) ?? [0.1, 0.1, 0.8, 0.8]),
        verified: m['verified'] ?? false,
      );

  Annotation copyWith({BBox? bbox, bool? verified}) => Annotation(
        brand: brand,
        subBrand: subBrand,
        volume: volume,
        material: material,
        fullLabel: fullLabel,
        bbox: bbox ?? this.bbox.copy(),
        verified: verified ?? this.verified,
      );

  Map<String, dynamic> toMap() => {
        'brand': brand,
        'sub_brand': subBrand,
        'volume': volume,
        'material': material,
        'full_label': fullLabel,
        'bbox_mode': 'normalized_0_1',
        'bbox': bbox.toList(),
        'verified': verified,
      };
}

class ImageRecord {
  final String imageId;
  final String shopContext;
  final int width;
  final int height;
  final List<Annotation> annotations;
  final String lighting;
  final String angle;
  final bool isEdgeCase;
  final String? edgeType;
  final String condition;
  final String occlusion;
  /// Phone/device model used to capture the image (e.g. "Pixel 6", "iPhone14,2").
  final String? deviceModel;
  // For unprocessed captures: needed when moving to context folder from nudge
  final String? shopName;
  final String? category;
  final String? variantLabel;

  ImageRecord({
    required this.imageId,
    required this.shopContext,
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
    this.shopName,
    this.category,
    this.variantLabel,
  });

  Map<String, dynamic> toJson() => {
        'image_id': imageId,
        'shop_context': shopContext,
        'image_size': {'width': width, 'height': height},
        'annotations': annotations.map((a) => a.toMap()).toList(),
        if (shopName != null) 'shop_name': shopName,
        if (category != null) 'category': category,
        if (variantLabel != null) 'variant_label': variantLabel,
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
