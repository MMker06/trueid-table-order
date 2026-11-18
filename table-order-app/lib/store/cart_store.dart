import 'package:flutter_riverpod/flutter_riverpod.dart';

class CartItem {
  final String menuItemId;
  final String name;
  final int price;
  final bool isAdultOnly;
  int quantity;

  CartItem({required this.menuItemId, required this.name, required this.price, required this.isAdultOnly, this.quantity = 1});

  int get total => price * quantity;
}

class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier() : super([]);

  void add(CartItem item) {
    final idx = state.indexWhere((e) => e.menuItemId == item.menuItemId);
    if (idx >= 0) {
      final updated = [...state];
      updated[idx].quantity++;
      state = updated;
    } else {
      state = [...state, item];
    }
  }

  void remove(String menuItemId) {
    final idx = state.indexWhere((e) => e.menuItemId == menuItemId);
    if (idx < 0) return;
    final updated = [...state];
    if (updated[idx].quantity > 1) {
      updated[idx].quantity--;
      state = updated;
    } else {
      updated.removeAt(idx);
      state = updated;
    }
  }

  void clear() => state = [];

  int get totalAmount => state.fold(0, (s, e) => s + e.total);
  bool get hasAdultItems => state.any((e) => e.isAdultOnly);
  int get itemCount => state.fold(0, (s, e) => s + e.quantity);
}

final cartProvider = StateNotifierProvider<CartNotifier, List<CartItem>>((ref) => CartNotifier());
