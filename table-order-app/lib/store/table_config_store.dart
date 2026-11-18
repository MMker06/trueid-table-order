import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TableConfig {
  final String merchantId;
  final String tableNumber;
  final String merchantName;
  const TableConfig({
    required this.merchantId,
    required this.tableNumber,
    required this.merchantName,
  });
}

class TableConfigState {
  final TableConfig? config;
  final bool isLoading;
  const TableConfigState({this.config, this.isLoading = true});
  bool get isConfigured => config != null;
}

class TableConfigNotifier extends StateNotifier<TableConfigState> {
  static const _storage = FlutterSecureStorage();

  TableConfigNotifier() : super(const TableConfigState()) { _load(); }

  Future<void> _load() async {
    try {
      final merchantId   = await _storage.read(key: 'tbl_merchant_id');
      final tableNumber  = await _storage.read(key: 'tbl_table_number');
      final merchantName = await _storage.read(key: 'tbl_merchant_name');
      if (merchantId != null && tableNumber != null) {
        state = TableConfigState(
          config: TableConfig(
            merchantId: merchantId,
            tableNumber: tableNumber,
            merchantName: merchantName ?? '',
          ),
          isLoading: false,
        );
        return;
      }
    } catch (_) {}
    state = const TableConfigState(isLoading: false);
  }

  Future<void> save(String merchantId, String tableNumber, String merchantName) async {
    await _storage.write(key: 'tbl_merchant_id', value: merchantId);
    await _storage.write(key: 'tbl_table_number', value: tableNumber);
    await _storage.write(key: 'tbl_merchant_name', value: merchantName);
    state = TableConfigState(
      config: TableConfig(
        merchantId: merchantId,
        tableNumber: tableNumber,
        merchantName: merchantName,
      ),
      isLoading: false,
    );
  }

  Future<void> clear() async {
    await _storage.delete(key: 'tbl_merchant_id');
    await _storage.delete(key: 'tbl_table_number');
    await _storage.delete(key: 'tbl_merchant_name');
    state = const TableConfigState(isLoading: false);
  }
}

final tableConfigProvider =
    StateNotifierProvider<TableConfigNotifier, TableConfigState>(
  (ref) => TableConfigNotifier(),
);
