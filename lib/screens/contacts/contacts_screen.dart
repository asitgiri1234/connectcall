import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../models/call_model.dart';
import '../../models/user_model.dart';
import '../../providers/user_providers.dart';
import '../../widgets/state_views.dart';
import '../../widgets/user_tile.dart';

/// Screen 4: the user directory, with search and per-user call buttons.
class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Seed from the shared provider so a query typed on Home is still
    // reflected here after a tab switch.
    _searchController.text = ref.read(searchQueryProvider);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    // Debounced so each keystroke does not rebuild the whole list. The filter
    // itself is local, but this keeps rebuilds cheap on long directories.
    _debounce?.cancel();
    _debounce = Timer(AppConstants.searchDebounce, () {
      ref.read(searchQueryProvider.notifier).update(value);
    });
  }

  void _startCall(UserModel user, CallType type) {
    // Wired up in Phase 3, once the signaling layer exists.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${type.label} to ${user.name} — coming in Phase 3'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(usersProvider);
    final filtered = ref.watch(filteredUsersProvider);
    final query = ref.watch(searchQueryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Contacts')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
                        onPressed: () {
                          _debounce?.cancel();
                          _searchController.clear();
                          ref.read(searchQueryProvider.notifier).clear();
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: usersAsync.when(
              loading: () => const LoadingView(message: 'Loading contacts'),
              error: (error, _) => ErrorView(
                error: error,
                onRetry: () => ref.invalidate(usersProvider),
              ),
              data: (allUsers) {
                final users = filtered.value ?? const <UserModel>[];

                // Two distinct empty states: nobody has registered yet, versus
                // a search that matched nothing. They need different guidance.
                if (allUsers.isEmpty) {
                  return const EmptyView(
                    icon: Icons.people_outline_rounded,
                    title: 'No contacts yet',
                    message:
                        'Register another account on a second device and it '
                        'will appear here.',
                  );
                }
                if (users.isEmpty) {
                  return EmptyView(
                    icon: Icons.search_off_rounded,
                    title: 'No matches',
                    message: 'Nobody matches "$query".',
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: users.length,
                  separatorBuilder: (_, index) => const Divider(indent: 76),
                  itemBuilder: (context, index) {
                    final user = users[index];
                    return UserTile(
                      user: user,
                      onCall: (type) => _startCall(user, type),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
