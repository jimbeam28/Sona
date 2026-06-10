// lib/shared/di/providers.dart
// Cross-feature provider bridge (REF-31).
//
// This is the ONLY file that is allowed to import from multiple features.
// It re-exports providers that are consumed across feature boundaries so that
// feature modules can import from a single canonical source instead of
// reaching into each other's internals.
//
// After REF-32, individual feature providers will import from this file
// rather than directly from other features, eliminating circular dependency
// chains such as browser <-> player.
//
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
        sharedPreferencesProvider,
        sortOptionProvider,
        directoryCacheProvider,
        clearDirectoryCacheProvider,
        directoryContentsProvider,
        navigationStackProvider,
        // Queue state
        currentPlayQueueProvider,
        lastQueueConnectionIdProvider,
        clearQueueOnConnectionSwitchProvider,
        persistQueueOnChangeProvider,
        restoreQueueFromPrefsProvider,
        // Progress bridge
        loadProgressForDirectoryProvider,
        playProgressProvider,
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
        audioHandlerProvider,
        playbackOrchestratorProvider,
        // Queue navigation
        loadAndPlayProvider,
        skipToNextProvider,
        skipToPreviousProvider,
        selectQueueIndexProvider,
        removeTrackFromQueueProvider,
        saveProgressProvider,
        // Speed
        defaultSpeedProvider,
        setDefaultSpeedProvider,
        currentSpeedProvider,
        seekStepProvider,
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
        backgroundPlaybackEnabledProvider,
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
        getDefaultSpeed,
        readSeekStep,
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
