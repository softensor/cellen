import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';

/// Responsive shell: sidebar on wide screens, bottom nav on narrow
class SidebarLayout extends StatelessWidget {
  final Widget child;
  final List<SidebarItem> items;
  final String currentPath;
  final String title;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  const SidebarLayout({
    super.key,
    required this.child,
    required this.items,
    required this.currentPath,
    required this.title,
    this.actions,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;
    if (isWide) {
      return _WideLayout(
          child: child,
          items: items,
          currentPath: currentPath,
          title: title,
          actions: actions,
          floatingActionButton: floatingActionButton);
    }
    return _NarrowLayout(
        child: child,
        items: items,
        currentPath: currentPath,
        title: title,
        actions: actions,
        floatingActionButton: floatingActionButton);
  }
}

class SidebarItem {
  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final int? badge;

  const SidebarItem({
    required this.path,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.badge,
  });
}

class _WideLayout extends StatelessWidget {
  final Widget child;
  final List<SidebarItem> items;
  final String currentPath;
  final String title;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  const _WideLayout({
    required this.child,
    required this.items,
    required this.currentPath,
    required this.title,
    this.actions,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 220,
            color: Colors.white,
            child: Column(
              children: [
                // Logo
                Container(
                  height: 60,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppTheme.border)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.school_rounded,
                            color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Cellen',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                ),
                // Nav items
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    children: items.map((item) {
                      final selected = currentPath.startsWith(item.path);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 2),
                        child: ListTile(
                          onTap: () => context.go(item.path),
                          selected: selected,
                          selectedTileColor: AppTheme.primaryLight,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                          minVerticalPadding: 0,
                          visualDensity: VisualDensity.compact,
                          leading: Icon(
                            selected ? item.selectedIcon : item.icon,
                            color: selected
                                ? AppTheme.primary
                                : AppTheme.textSecondary,
                            size: 20,
                          ),
                          title: Text(
                            item.label,
                            style: TextStyle(
                              color: selected
                                  ? AppTheme.primary
                                  : AppTheme.textSecondary,
                              fontSize: 14,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                          trailing: item.badge != null && item.badge! > 0
                              ? Container(
                                  width: 20,
                                  height: 20,
                                  decoration: const BoxDecoration(
                                    color: AppTheme.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      item.badge! > 9
                                          ? '9+'
                                          : '${item.badge}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                )
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          // Vertical divider
          const VerticalDivider(width: 1, thickness: 1, color: AppTheme.border),
          // Main content
          Expanded(
            child: Column(
              children: [
                // Top bar
                Container(
                  height: 60,
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const Spacer(),
                      if (actions != null) ...actions!,
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 1, color: AppTheme.border),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: floatingActionButton,
    );
  }
}

class _NarrowLayout extends StatelessWidget {
  final Widget child;
  final List<SidebarItem> items;
  final String currentPath;
  final String title;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  const _NarrowLayout({
    required this.child,
    required this.items,
    required this.currentPath,
    required this.title,
    this.actions,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    // show max 5 items in bottom nav, rest accessible from drawer
    final navItems = items.take(5).toList();
    final currentIndex = navItems.indexWhere(
        (i) => currentPath.startsWith(i.path));

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text(title),
        actions: actions,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: AppTheme.border),
        ),
      ),
      body: child,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex < 0 ? 0 : currentIndex,
        onDestinationSelected: (i) => context.go(navItems[i].path),
        backgroundColor: Colors.white,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppTheme.primaryLight,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: navItems
            .map((item) => NavigationDestination(
                  icon: Icon(item.icon, color: AppTheme.textSecondary),
                  selectedIcon: Icon(item.selectedIcon, color: AppTheme.primary),
                  label: item.label,
                ))
            .toList(),
      ),
    );
  }
}
