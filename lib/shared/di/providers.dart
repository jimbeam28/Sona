// lib/shared/di/providers.dart
// Cross-feature provider re-export facade.
//
// This file re-exports providers from multiple features so that consumers
// can import from a single canonical source instead of reaching into each
// other's internals.  It does NOT own any business logic — all providers
// are defined in their respective feature modules.
//
// Feature modules MAY import pure-domain symbols directly from other
// features' domain/ directories (no feature-isolation violation), but
// should prefer this facade for provider access to keep import graphs
// shallow and auditable.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Organisation:
//   1. Browser feature  — queue, sort, cache, directory providers
//   2. Connection feature — active connection, validation, DAO, storage
//   3. Player feature — audio player, playback orchestrator, speed, mode
//   4. Progress feature — DAO, upsert, resume dialog
//   5. Timer feature — timer service, state, actions
//   6. Settings feature — theme, seek step, remember speed
//   7. Playlist feature — CRUD, tracks, export/import

// ── 1. Browser ──────────────────────────────────────────────────────────────

export '../../features/browser/browser_provider.dart'
    show
        // Infrastructure
        sortOptionProvider,
        SortOption,
        SortOptionNotifier,
        directoryCacheProvider,
        clearDirectoryCacheProvider,
        directoryContentsProvider,
        navigationStackProvider,
        NavigationStackNotifier,
        // Queue state
        currentPlayQueueProvider,
        lastQueueConnectionIdProvider,
        clearQueueOnConnectionSwitchProvider,
        persistQueueOnChangeProvider,
        restoreQueueFromPrefsProvider,
        // Re-exports
        preloadAudioSource,
        sortFiles;

// ── 2. Connection ───────────────────────────────────────────────────────────

export '../../features/connection/connection_provider.dart'
    show
        // Infrastructure
        connectionDaoProvider,
        webDavClientProvider,
        secureStorageProvider,
        connectionServiceProvider,
        connectionSaverProvider,
        connectionUpdaterProvider,
        // Active connection
        activeConnectionProvider,
        connectionListProvider,
        // Validation
        connectionValidatorProvider,
        startupValidationProvider,
        ConnectionValidationState,
        ValidationIdle,
        ValidationLoading,
        ValidationSuccess,
        ValidationError,
        // Use-cases
        switchActiveConnectionProvider,
        deleteConnectionProvider,
        ConnectionSaver,
        ConnectionUpdater;

// ── 3. Player ───────────────────────────────────────────────────────────────

export '../../features/player/player_provider.dart'
    show
        // Infrastructure
        audioPlayerProvider,
        audioPlayingProvider,
        audioHandlerProvider,
        playbackOrchestratorProvider,
        // Queue navigation
        loadAndPlayProvider,
        skipToNextProvider,
        skipToPreviousProvider,
        selectQueueIndexProvider,
        removeTrackFromQueueProvider,
        insertAfterCurrentProvider,
        saveProgressProvider,
        // Speed
        defaultSpeedProvider,
        setDefaultSpeedProvider,
        // Play mode
        playModeProvider,
        nextPlayModeProvider,
        iconForPlayMode,
        // Processing listeners
        startProcessingListenerProvider,
        cancelProcessingListenerProvider,
        reconnectPlaybackListenersProvider,
        cancelPlaybackSubscriptionsProvider,
        // Startup restore
        restoreStartupProgressProvider,
        backgroundPlaybackSyncProvider,
        // Pure functions
        sanitizeResumePosition,
        applyLatestProgressToQueue,
        // Re-exports from domain
        PlayMode,
        labelForPlayMode,
        PlayerLoadStatus,
        PlayerLoadState,
        SerializedRequestGate,
        TrackLoadResult,
        TrackLoadStatus,
        speedOptions,
        isValidSpeed,
        seekStepPrefsKey,
        defaultSeekStep,
        formatDuration,
        AudioFocusState,
        BackgroundPlaybackConfig,
        BackgroundPlaybackNotifier,
        BackgroundPlaybackState,
        MediaControlAction,
        backgroundPlaybackProvider,
        computePlaybackStateAfterLifecycle,
        shouldContinueInBackground;

// ── 4. Progress ─────────────────────────────────────────────────────────────

export '../../features/progress/domain/progress_service.dart'
    show ResumeDialogState;

export '../../features/progress/progress_provider.dart'
    show
        // Infrastructure
        progressDaoProvider,
        progressServiceProvider,
        // Query
        progressForFileProvider,
        recentlyPlayedProvider,
        latestPlayedProgressProvider,
        // Mutation
        upsertProgressProvider,
        clearProgressProvider,
        // Resume dialog
        ProgressResumeNotifier,
        progressResumeProvider;

// ── 5. Timer ────────────────────────────────────────────────────────────────

export '../../features/timer/timer_provider.dart'
    show
        // Infrastructure
        timerServiceProvider,
        timerStateProvider,
        TimerStateNotifier,
        // Derived
        timerActiveProvider,
        timerModeProvider,
        remainingTimeProvider,
        formattedRemainingProvider,
        // Actions
        startDurationTimerProvider,
        startAfterCurrentProvider,
        cancelTimerProvider,
        checkTimerExpiryProvider,
        onTrackCompletedProvider,
        // Settings
        lastCustomTimerMinutesKey,
        readLastCustomTimerMinutes,
        lastCustomTimerMinutesProvider,
        setLastCustomTimerMinutesProvider;

export '../../features/timer/widgets/timer_button.dart' show TimerBottomSheet;

// ── 6. Settings ─────────────────────────────────────────────────────────────

export '../../features/settings/settings_provider.dart'
    show
        // Theme
        themeModeProvider,
        setThemeModeProvider,
        getThemeMode,
        setThemeMode,
        labelForThemeMode,
        // Seek step
        seekStepSettingProvider,
        setSeekStepSettingProvider,
        seekStepOptions,
        setSeekStep,
        labelForSeekStep,
        // Remember speed
        rememberSpeedProvider,
        setRememberSpeedProvider,
        getRememberSpeed;

// ── 7. Playlist ─────────────────────────────────────────────────────────────

export '../../features/playlist/playlist_provider.dart'
    show
        // Infrastructure
        playlistDaoProvider,
        // Sort
        PlaylistSortOption,
        TrackSortOption,
        playlistSortProvider,
        trackSortProvider,
        // Data
        playlistListProvider,
        playlistTracksProvider,
        // Mutation
        createPlaylistProvider,
        deletePlaylistProvider,
        updatePlaylistProvider,
        addTracksToPlaylistProvider,
        reorderPlaylistTrackProvider,
        removeTracksFromPlaylistProvider,
        // Export / Import
        exportPlaylistProvider,
        importPlaylistProvider;

// ── 8. Cross-feature widgets & dialogs ──────────────────────────────────────

export '../../features/progress/progress_dialog.dart'
    show showProgressResumeDialog;
export '../../features/browser/browser_screen.dart' show BrowserScreen;
export '../../features/browser/widgets/breadcrumb_bar.dart' show BreadcrumbBar;
export '../../features/timer/domain/timer_service.dart'
    show TimerMode, TimerService;
export '../../features/playlist/playlist_list_screen.dart'
    show PlaylistListScreen;
export '../../features/player/widgets/mini_player_bar.dart' show MiniPlayerBar;

// ── Infrastructure ───────────────────────────────────────────────────────────

/// Global SharedPreferences provider — infrastructure moved here from
/// browser_provider.dart (REF-04-S4).  Production overrides it with the
/// real instance; tests override it with mock prefs or leave it null.
///
/// Defined after the exports so that the re-export facade stays
/// directive-first (REF-04-S4/DI2).
final sharedPreferencesProvider = Provider<SharedPreferences?>((ref) => null);
