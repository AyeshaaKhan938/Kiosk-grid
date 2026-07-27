/// Product category returned by vms-cloud for kiosk browsing/filtering.
class ProductCategory {
  final int id;
  final String name;
  final String? slug;
  final String? iconUrl;
  final int sortOrder;

  const ProductCategory({
    required this.id,
    required this.name,
    this.slug,
    this.iconUrl,
    this.sortOrder = 0,
  });

  factory ProductCategory.fromJson(Map<String, dynamic> json) {
    return ProductCategory(
      id:        (json['id'] as num).toInt(),
      name:      json['name'] as String? ?? 'Category',
      slug:      json['slug'] as String?,
      iconUrl:   json['icon_url'] as String?,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}
