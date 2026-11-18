import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';

final _categoriesProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  return ref.read(apiClientProvider).getCategories();
});
final _menuItemsProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  return ref.read(apiClientProvider).getMenuItems();
});

class MenuManagementScreen extends ConsumerStatefulWidget {
  const MenuManagementScreen({super.key});

  @override
  ConsumerState<MenuManagementScreen> createState() => _MenuManagementScreenState();
}

class _MenuManagementScreenState extends ConsumerState<MenuManagementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(_categoriesProvider);
    ref.invalidate(_menuItemsProvider);
  }

  // ── 카테고리 추가 ─────────────────────────────────────────
  Future<void> _showAddCategoryDialog() async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('카테고리 추가', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        content: _dlgField('카테고리 이름 (예: 고기, 주류, 음료)', ctrl),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(
            onPressed: () async {
              if (ctrl.text.trim().isEmpty) return;
              await ref.read(apiClientProvider).createCategory(ctrl.text.trim());
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              _refresh();
            },
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
            child: const Text('추가'),
          ),
        ],
      ),
    );
  }

  // ── 메뉴 아이템 추가/편집 ──────────────────────────────────
  Future<void> _showItemDialog({Map<String, dynamic>? existing}) async {
    final categories = await ref.read(_categoriesProvider.future);
    if (!mounted) return;

    final nameCtrl  = TextEditingController(text: existing?['name'] as String? ?? '');
    final priceCtrl = TextEditingController(text: existing?['price']?.toString() ?? '');
    final descCtrl  = TextEditingController(text: existing?['description'] as String? ?? '');
    final imgCtrl   = TextEditingController(text: existing?['image_url'] as String? ?? '');
    String? selectedCatId = existing?['category_id'] as String?;
    if (selectedCatId == null && categories.isNotEmpty) {
      selectedCatId = categories.first['id'] as String;
    }
    bool isAdultOnly = existing?['is_adult_only'] as bool? ?? false;
    final isEdit = existing != null;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(isEdit ? '메뉴 수정' : '메뉴 추가',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 340,
              child: Column(mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                _dlgField('메뉴 이름', nameCtrl),
                const Gap(12),
                _dlgField('가격', priceCtrl, type: TextInputType.number),
                const Gap(12),
                _dlgField('설명 (선택)', descCtrl),
                const Gap(12),
                _dlgField('이미지 URL (선택)', imgCtrl),
                const Gap(12),
                const Text('카테고리',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const Gap(4),
                if (categories.isEmpty)
                  const Text('카테고리를 먼저 추가해주세요',
                      style: TextStyle(fontSize: 12, color: Colors.red))
                else
                  DropdownButtonFormField<String>(
                    value: selectedCatId,
                    onChanged: (v) => setS(() => selectedCatId = v),
                    items: categories.map<DropdownMenuItem<String>>((c) =>
                        DropdownMenuItem(
                          value: c['id'] as String,
                          child: Text(c['name'] as String),
                        )).toList(),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                const Gap(8),
                GestureDetector(
                  onTap: () => setS(() => isAdultOnly = !isAdultOnly),
                  child: Row(children: [
                    Checkbox(
                      value: isAdultOnly,
                      onChanged: (v) => setS(() => isAdultOnly = v!),
                      activeColor: const Color(0xFFD97706),
                    ),
                    const Text('성인 전용 (주류 등)',
                        style: TextStyle(fontSize: 13)),
                  ]),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
                child: const Text('취소')),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.isEmpty || priceCtrl.text.isEmpty) return;
                final data = {
                  'name': nameCtrl.text.trim(),
                  'price': int.parse(priceCtrl.text),
                  'description': descCtrl.text.trim(),
                  'image_url': imgCtrl.text.trim().isEmpty
                      ? null
                      : imgCtrl.text.trim(),
                  'category_id': selectedCatId,
                  'is_adult_only': isAdultOnly,
                };
                if (isEdit) {
                  await ref.read(apiClientProvider)
                      .updateMenuItem(existing!['id'] as String, data);
                } else {
                  await ref.read(apiClientProvider).createMenuItem(data);
                }
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                _refresh();
              },
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB)),
              child: Text(isEdit ? '저장' : '추가'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteItem(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('메뉴 삭제'),
        content: const Text('이 메뉴를 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(apiClientProvider).deleteMenuItem(id);
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Color(0xFF111827)),
          onPressed: () => context.pop(),
        ),
        title: const Text('메뉴 관리',
            style: TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.w700,
                fontSize: 17)),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: const Color(0xFF2563EB),
          unselectedLabelColor: const Color(0xFF9CA3AF),
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          indicatorColor: const Color(0xFF2563EB),
          dividerColor: const Color(0xFFE5E7EB),
          tabs: const [Tab(text: '메뉴'), Tab(text: '카테고리')],
        ),
      ),
      body: TabBarView(controller: _tabCtrl, children: [
        _MenuTab(
          onAdd: () => _showItemDialog(),
          onEdit: (item) => _showItemDialog(existing: item),
          onDelete: _deleteItem,
          refresh: _refresh,
        ),
        _CategoryTab(refresh: _refresh, onAdd: _showAddCategoryDialog),
      ]),
    );
  }

  Widget _dlgField(String label, TextEditingController ctrl,
      {TextInputType type = TextInputType.text}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const Gap(4),
        TextField(
          controller: ctrl,
          keyboardType: type,
          inputFormatters: type == TextInputType.number
              ? [FilteringTextInputFormatter.digitsOnly]
              : [],
          decoration: InputDecoration(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ]);
}

// ── 메뉴 탭 ──────────────────────────────────────────────────
class _MenuTab extends ConsumerWidget {
  final VoidCallback onAdd;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final ValueChanged<String> onDelete;
  final VoidCallback refresh;

  const _MenuTab({
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.refresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(_menuItemsProvider);
    final cats  = ref.watch(_categoriesProvider);

    final catMap = <String, String>{};
    cats.whenData((list) {
      for (final c in list) {
        catMap[c['id'] as String] = c['name'] as String;
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: onAdd,
        backgroundColor: const Color(0xFF2563EB),
        icon: const Icon(Icons.add_rounded),
        label: const Text('메뉴 추가'),
      ),
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (list) => list.isEmpty
            ? const Center(child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.menu_book_outlined, size: 64, color: Color(0xFFD1D5DB)),
                  Gap(16),
                  Text('등록된 메뉴가 없습니다',
                      style: TextStyle(color: Color(0xFF6B7280))),
                ]))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: list.length,
                itemBuilder: (ctx, i) {
                  final item = list[i] as Map<String, dynamic>;
                  final catId = item['category_id'] as String?;
                  final catName = catId != null ? (catMap[catId] ?? '미분류') : '미분류';
                  final imageUrl = item['image_url'] as String?;
                  final isAdult = item['is_adult_only'] as bool? ?? false;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Row(children: [
                      // 이미지 썸네일
                      ClipRRect(
                        borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(14)),
                        child: SizedBox(
                          width: 72,
                          height: 72,
                          child: imageUrl != null && imageUrl.isNotEmpty
                              ? Image.network(imageUrl, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _placeholder())
                              : _placeholder(),
                        ),
                      ),
                      const Gap(12),
                      Expanded(child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Row(children: [
                            Text(item['name'] as String,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14)),
                            if (isAdult) ...[
                              const Gap(6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('성인',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFFD97706),
                                        fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ]),
                          const Gap(2),
                          Text(
                            '${(item['price'] as num).toInt().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}원  ·  $catName',
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF6B7280)),
                          ),
                          if (imageUrl == null || imageUrl.isEmpty)
                            const Text('이미지 없음',
                                style: TextStyle(
                                    fontSize: 11, color: Color(0xFFD1D5DB))),
                        ]),
                      )),
                      // 편집/삭제
                      Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined,
                              size: 18, color: Color(0xFF6B7280)),
                          onPressed: () => onEdit(item),
                          tooltip: '수정',
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 18, color: Color(0xFFEF4444)),
                          onPressed: () => onDelete(item['id'] as String),
                          tooltip: '삭제',
                        ),
                      ]),
                    ]),
                  );
                },
              ),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: const Color(0xFFF3F4F6),
        child: const Icon(Icons.restaurant_rounded,
            size: 28, color: Color(0xFFD1D5DB)),
      );
}

// ── 카테고리 탭 ───────────────────────────────────────────────
class _CategoryTab extends ConsumerWidget {
  final VoidCallback refresh;
  final VoidCallback onAdd;
  const _CategoryTab({required this.refresh, required this.onAdd});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = ref.watch(_categoriesProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: onAdd,
        backgroundColor: const Color(0xFF059669),
        icon: const Icon(Icons.add_rounded),
        label: const Text('카테고리 추가'),
      ),
      body: cats.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (list) => list.isEmpty
            ? const Center(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  Icon(Icons.category_outlined,
                      size: 64, color: Color(0xFFD1D5DB)),
                  Gap(16),
                  Text('등록된 카테고리가 없습니다',
                      style: TextStyle(color: Color(0xFF6B7280))),
                  Gap(8),
                  Text('카테고리 추가 버튼으로 탭을 만들어보세요',
                      style: TextStyle(
                          fontSize: 12, color: Color(0xFF9CA3AF))),
                ]))
            : ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: list.length,
                onReorder: (_, __) {},
                itemBuilder: (ctx, i) {
                  final cat = list[i] as Map<String, dynamic>;
                  return Container(
                    key: ValueKey(cat['id']),
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.drag_handle_rounded,
                          color: Color(0xFFD1D5DB)),
                      const Gap(12),
                      Expanded(
                          child: Text(cat['name'] as String,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600))),
                    ]),
                  );
                },
              ),
      ),
    );
  }
}
