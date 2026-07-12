class FoodMenuItemEntry {
  final int dayOfWeek;
  final String mealType;
  final String? mealComponent;

  const FoodMenuItemEntry({
    required this.dayOfWeek,
    required this.mealType,
    this.mealComponent,
  });

  factory FoodMenuItemEntry.fromJson(Map<String, dynamic> json) {
    return FoodMenuItemEntry(
      dayOfWeek: (json['day_of_week'] as num?)?.toInt() ?? 1,
      mealType: json['meal_type'] as String? ?? '',
      mealComponent: json['meal_component'] as String?,
    );
  }
}

class FoodMenu {
  final String id;
  final String schoolId;
  final String level;
  final DateTime startDate;
  final DateTime endDate;
  final List<FoodMenuItemEntry> items;

  const FoodMenu({
    required this.id,
    required this.schoolId,
    required this.level,
    required this.startDate,
    required this.endDate,
    required this.items,
  });

  factory FoodMenu.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? [];
    return FoodMenu(
      id: json['id']?.toString() ?? '',
      schoolId: json['school_id']?.toString() ?? '',
      level: json['level'] as String? ?? '',
      startDate: json['start_date'] != null
          ? DateTime.tryParse(json['start_date'] as String) ?? DateTime.now()
          : DateTime.now(),
      endDate: json['end_date'] != null
          ? DateTime.tryParse(json['end_date'] as String) ?? DateTime.now()
          : DateTime.now(),
      items: rawItems
          .map((e) => FoodMenuItemEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
