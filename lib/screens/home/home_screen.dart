import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/router/routes.dart';
import '../../models/call_history_entry.dart';
import '../../models/user_model.dart';
import '../../providers/auth_providers.dart';
import '../../providers/history_providers.dart';
import '../../providers/user_providers.dart';
import '../../widgets/call_launcher.dart';
import '../../widgets/history_tile.dart';
import '../../widgets/state_views.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/user_tile.dart';

/// Screen 3: profile header, search, contacts and recent calls.
///
/// A summary rather than a second copy of Contacts: it shows who is online
/// and the first few contacts, with "See all" handing off to the full list.
/// The search box shares its query with Contacts, so switching tabs mid-search
/// keeps the results.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static const _previewCount = 5;

  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController.text = ref.read(searchQueryProvider);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(AppConstants.searchDebounce, () {
      ref.read(searchQueryProvider.notifier).update(value);
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    ref.read(searchQueryProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = ref.watch(currentUserProvider).value;
    final usersAsync = ref.watch(usersProvider);
    final filtered = ref.watch(filteredUsersProvider).value ?? const [];
    final query = ref.watch(searchQueryProvider);
    final recent =
        ref.watch(recentCallsProvider).value ?? const <CallHistoryEntry>[];

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(usersProvider);
            ref.invalidate(callHistoryProvider);
          },
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _Header(me: me)),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search people...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded),
                              tooltip: 'Clear search',
                              onPressed: _clearSearch,
                            ),
                    ),
                  ),
                ),
              ),

              ...usersAsync.when(
                loading: () => [
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 220, child: LoadingView()),
                  ),
                ],
                error: (error, _) => [
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 320,
                      child: ErrorView(
                        error: error,
                        onRetry: () => ref.invalidate(usersProvider),
                      ),
                    ),
                  ),
                ],
                data: (all) => _contactSlivers(
                  context,
                  all: all,
                  filtered: filtered,
                  query: query,
                ),
              ),

              SliverToBoxAdapter(
                child: _SectionHeader(
                  title: 'Recent calls',
                  theme: theme,
                  action: recent.isEmpty
                      ? null
                      : TextButton(
                          onPressed: () => context.go(Routes.history),
                          child: const Text('See all'),
                        ),
                ),
              ),
              if (recent.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: _RecentCallsPlaceholder(),
                  ),
                )
              else
                SliverList.list(
                  children: [
                    for (final entry in recent)
                      HistoryTile(
                        entry: entry,
                        onCallBack: () => callBack(context, ref, entry),
                      ),
                    const SizedBox(height: 24),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _contactSlivers(
    BuildContext context, {
    required List<UserModel> all,
    required List<UserModel> filtered,
    required String query,
  }) {
    final theme = Theme.of(context);

    if (all.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: _SectionHeader(title: 'Contacts', theme: theme),
        ),
        const SliverToBoxAdapter(
          child: SizedBox(
            height: 240,
            child: EmptyView(
              icon: Icons.people_outline_rounded,
              title: 'No contacts yet',
              message: 'Register another account on a second device and it '
                  'will appear here.',
            ),
          ),
        ),
      ];
    }

    final online = all.where((u) => u.isOnline).toList();
    final preview = filtered.take(_previewCount).toList();

    return [
      // "Online now" only makes sense when browsing, not mid-search.
      if (query.isEmpty && online.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: _SectionHeader(title: 'Online now', theme: theme),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: online.length,
              separatorBuilder: (_, index) => const SizedBox(width: 14),
              itemBuilder: (context, index) =>
                  _OnlineChip(user: online[index]),
            ),
          ),
        ),
      ],

      SliverToBoxAdapter(
        child: _SectionHeader(
          title: query.isEmpty ? 'Contacts' : 'Results',
          theme: theme,
          action: filtered.length > _previewCount
              ? TextButton(
                  onPressed: () => context.go(Routes.contacts),
                  child: const Text('See all'),
                )
              : null,
        ),
      ),

      if (preview.isEmpty)
        SliverToBoxAdapter(
          child: SizedBox(
            height: 200,
            child: EmptyView(
              icon: Icons.search_off_rounded,
              title: 'No matches',
              message: 'Nobody matches "$query".',
            ),
          ),
        )
      else
        SliverList.separated(
          itemCount: preview.length,
          separatorBuilder: (_, index) => const Divider(indent: 76),
          itemBuilder: (context, index) {
            final user = preview[index];
            return UserTile(
              user: user,
              onCall: (type) => launchCall(
                context,
                ref,
                callee: user,
                type: type,
              ),
            );
          },
        ),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.me});

  final UserModel? me;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = me;
    final firstName = user?.name.split(' ').first ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  firstName.isEmpty ? 'Hello' : 'Hi, $firstName',
                  style: theme.textTheme.headlineMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  AppConstants.tagline,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (user != null)
            Semantics(
              button: true,
              label: 'Your profile',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => context.go(Routes.profile),
                child: UserAvatar(user: user, radius: 24, showPresence: true),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.theme, this.action});

  final String title;
  final ThemeData theme;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
      child: Row(
        children: [
          Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
          ?action,
        ],
      ),
    );
  }
}

class _OnlineChip extends StatelessWidget {
  const _OnlineChip({required this.user});

  final UserModel user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 64,
      child: Column(
        children: [
          UserAvatar(user: user, radius: 28, showPresence: true),
          const SizedBox(height: 6),
          Text(
            user.name.split(' ').first,
            style: theme.textTheme.labelSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _RecentCallsPlaceholder extends StatelessWidget {
  const _RecentCallsPlaceholder();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.history_rounded, color: theme.textTheme.bodySmall?.color),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'No calls yet. Your recent calls will appear here.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.textTheme.bodySmall?.color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
