// lib/features/home/home_screen.dart
// Home screen with Tab navigation: Playlists | File Browser.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/background_service.dart';
import '../browser/browser_provider.dart';
import '../browser/browser_screen.dart';
import '../playlist/playlist_list_screen.dart';
import '../playlist/playlist_provider.dart';
import '../player/player_provider.dart';
import '../player/widgets/mini_player_bar.dart';
import '../timer/timer_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabController;

  static const _tabIndexKey = 'home_tab_index';

  Timer? _timerExpiryChecker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 2, vsync: this);

    // HOM-01: restore persisted tab index
    final prefs = ref.read(sharedPreferencesProvider);
    final savedIndex = prefs?.getInt(_tabIndexKey) ?? 0;
    if (savedIndex >= 0 && savedIndex < 2) {
      _tabController.index = savedIndex;
    }

    // HOM-01: persist tab index on change
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        prefs?.setInt(_tabIndexKey, _tabController.index);
      }
    });

    // TMR-05: check for duration-timer expiry every second so the countdown
    // works even when the full PlayerScreen is not visible.
    _timerExpiryChecker = Timer.periodic(const Duration(seconds: 1), (_) {
      final expired = ref.read(checkTimerExpiryProvider)();
      if (expired) {
        ref.read(audioPlayerProvider).pause();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final expired = ref.read(checkTimerExpiryProvider)();
      if (expired) {
        ref.read(audioPlayerProvider).pause();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timerExpiryChecker?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // PLY-F: eagerly wire NasAudioHandler.onConfigChanged → BackgroundPlaybackNotifier
    ref.read(backgroundPlaybackSyncProvider);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          moveTaskToBack();
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Sona'),
        centerTitle: true,
        actions: [
          if (_tabController.index == 0) _playlistSortMenu(),
          if (_tabController.index == 1) _browserSortMenu(),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            labelColor: Theme.of(context).colorScheme.primary,
            tabs: const [
              Tab(text: '播放单'),
              Tab(text: '文件浏览器'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                PlaylistListScreen(),
                BrowserScreen(),
              ],
            ),
          ),
          const MiniPlayerBar(),
        ],
      ),
    ));
  }

  Widget _playlistSortMenu() {
    return PopupMenuButton<PlaylistSortOption>(
      icon: const Icon(Icons.sort),
      tooltip: '排序方式',
      onSelected: (option) {
        ref.read(playlistSortProvider.notifier).state = option;
      },
      itemBuilder: (context) {
        final current = ref.watch(playlistSortProvider);
        return [
          _sortItem('创建时间升序', PlaylistSortOption.createdAsc, current),
          _sortItem('创建时间降序', PlaylistSortOption.createdDesc, current),
          _sortItem('名称升序', PlaylistSortOption.nameAsc, current),
          _sortItem('名称降序', PlaylistSortOption.nameDesc, current),
        ];
      },
    );
  }

  Widget _browserSortMenu() {
    return PopupMenuButton<SortOption>(
      icon: const Icon(Icons.sort),
      tooltip: '排序方式',
      onSelected: (option) {
        ref.read(sortOptionProvider.notifier).setOption(option);
      },
      itemBuilder: (context) {
        final current = ref.watch(sortOptionProvider);
        return [
          _browserSortItem('名称升序', SortOption.nameAsc, current),
          _browserSortItem('名称降序', SortOption.nameDesc, current),
          _browserSortItem('修改时间', SortOption.modifiedDesc, current),
        ];
      },
    );
  }

  PopupMenuItem<T> _sortItem<T>(
      String title, T value, T current) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          if (current == value)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(Icons.check,
                  size: 18, color: Theme.of(context).colorScheme.primary),
            )
          else
            const SizedBox(width: 26),
          Text(title),
        ],
      ),
    );
  }

  PopupMenuItem<SortOption> _browserSortItem(
      String title, SortOption value, SortOption current) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          if (current == value)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(Icons.check,
                  size: 18, color: Theme.of(context).colorScheme.primary),
            )
          else
            const SizedBox(width: 26),
          Text(title),
        ],
      ),
    );
  }
}
