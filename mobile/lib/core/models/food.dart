class FoodMenuItem {
  final String id;
  final String schoolId;
  final DateTime menuDate;
  final String? breakfast;
  final String? lunchSoup;
  final String? lunchMain;
  final String? lunchDessert;
  final String? lunchDrink;
  final String? snack;
  final String? notes;

  const FoodMenuItem({
    required this.id,
    required this.schoolId,
    required this.menuDate,
    this.breakfast,
    this.lunchSoup,
    this.lunchMain,
    this.lunchDessert,
    this.lunchDrink,
    this.snack,
    this.notes,
  });

  String get weekdayLabel {
    const labels = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
    final index = menuDate.weekday - 1;
    return index >= 0 && index < labels.length ? labels[index] : '';
  }

  factory FoodMenuItem.fromJson(Map<String, dynamic> json) {
    return FoodMenuItem(
      id: json['id']?.toString() ?? '',
      schoolId: json['school_id']?.toString() ?? '',
      menuDate: json['menu_date'] != null
          ? DateTime.tryParse(json['menu_date'] as String) ?? DateTime.now()
          : DateTime.now(),
      breakfast: json['breakfast'] as String?,
      lunchSoup: json['lunch_soup'] as String?,
      lunchMain: json['lunch_main'] as String?,
      lunchDessert: json['lunch_dessert'] as String?,
      lunchDrink: json['lunch_drink'] as String?,
      snack: json['snack'] as String?,
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'school_id': schoolId,
        'menu_date':
            '${menuDate.year.toString().padLeft(4, '0')}-${menuDate.month.toString().padLeft(2, '0')}-${menuDate.day.toString().padLeft(2, '0')}',
        if (breakfast != null) 'breakfast': breakfast,
        if (lunchSoup != null) 'lunch_soup': lunchSoup,
        if (lunchMain != null) 'lunch_main': lunchMain,
        if (lunchDessert != null) 'lunch_dessert': lunchDessert,
        if (lunchDrink != null) 'lunch_drink': lunchDrink,
        if (snack != null) 'snack': snack,
        if (notes != null) 'notes': notes,
      };
}
