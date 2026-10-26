class Product {
  const Product({
    required this.id,
    required this.name,
    this.code,
    this.category,
    this.unit = 'قطعة',
    this.brand,
    this.notes,
    this.isFavorite = false,
    this.isArchived = false,
    this.latestPurchasePrice,
    this.latestPurchaseDate,
    this.latestPurchaseCurrency = 'YER',
    this.latestSalePrice,
    this.latestSaleDate,
    this.latestSaleCurrency = 'YER',
    this.purchaseCount = 0,
    this.saleCount = 0,
  });

  final int id;
  final String name;
  final String? code;
  final String? category;
  final String unit;
  final String? brand;
  final String? notes;
  final bool isFavorite;
  final bool isArchived;
  final double? latestPurchasePrice;
  final String? latestPurchaseDate;
  final String? latestPurchaseCurrency;
  final double? latestSalePrice;
  final String? latestSaleDate;
  final String? latestSaleCurrency;
  final int purchaseCount;
  final int saleCount;

  factory Product.fromMap(Map<String, Object?> map) => Product(
        id: (map['id'] as num).toInt(),
        name: map['name'] as String,
        code: map['code'] as String?,
        category: map['category'] as String?,
        unit: (map['unit'] as String?) ?? 'قطعة',
        brand: map['brand'] as String?,
        notes: map['notes'] as String?,
        isFavorite: ((map['is_favorite'] as num?)?.toInt() ?? 0) == 1,
        isArchived: ((map['is_archived'] as num?)?.toInt() ?? 0) == 1,
        latestPurchasePrice: (map['latest_purchase_price'] as num?)?.toDouble(),
        latestPurchaseDate: map['latest_purchase_date'] as String?,
        latestPurchaseCurrency: map['latest_purchase_currency'] as String? ?? 'YER',
        latestSalePrice: (map['latest_sale_price'] as num?)?.toDouble(),
        latestSaleDate: map['latest_sale_date'] as String?,
        latestSaleCurrency: map['latest_sale_currency'] as String? ?? 'YER',
        purchaseCount: ((map['purchase_count'] as num?)?.toInt() ?? 0),
        saleCount: ((map['sale_count'] as num?)?.toInt() ?? 0),
      );
}
