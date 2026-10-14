class PriceEntry {
  const PriceEntry({
    required this.id,
    required this.productId,
    required this.date,
    required this.unitPrice,
    required this.quantity,
    this.partyName,
    this.currencyCode = 'YER',
    this.invoiceNumber,
    this.notes,
  });

  final int id;
  final int productId;
  final String date;
  final double unitPrice;
  final double quantity;
  final String? partyName;
  final String currencyCode;
  final String? invoiceNumber;
  final String? notes;

  factory PriceEntry.fromMap(Map<String, Object?> map) => PriceEntry(
        id: (map['id'] as num).toInt(),
        productId: (map['product_id'] as num).toInt(),
        date: map['entry_date'] as String,
        unitPrice: (map['unit_price'] as num).toDouble(),
        quantity: (map['quantity'] as num).toDouble(),
        partyName: map['party_name'] as String?,
        currencyCode: map['currency_code'] as String? ?? 'YER',
        invoiceNumber: map['invoice_number'] as String?,
        notes: map['notes'] as String?,
      );
}
