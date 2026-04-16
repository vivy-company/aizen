import AppKit
import Foundation
import GhosttyKit
import OSLog

@MainActor
extension Ghostty.App {
    /// Clean up the ghostty app resources
    func cleanup() {
        idleCleanupTask?.cancel()
        idleCleanupTask = nil

        DistributedNotificationCenter.default().removeObserver(self)
        NotificationCenter.default.removeObserver(self)

        if let observer = appearanceSettingObserver {
            NotificationCenter.default.removeObserver(observer)
            appearanceSettingObserver = nil
        }

        activeSurfaces.removeAll(keepingCapacity: false)
        lastKnownAppearance = nil
        lastKnownTheme = nil

        if let app = self.app {
            ghostty_app_free(app)
            self.app = nil
        }

        readiness = .loading
    }

    func appTick() {
        guard let app = self.app else { return }
        ghostty_app_tick(app)
    }

    /// Register a surface for config update tracking
    /// Returns the surface reference that should be stored by the view
    @discardableResult
    func registerSurface(_ surface: ghostty_surface_t) -> Ghostty.SurfaceReference {
        idleCleanupTask?.cancel()
        idleCleanupTask = nil

        let ref = Ghostty.SurfaceReference(surface)
        activeSurfaces.append(ref)
        activeSurfaces = activeSurfaces.filter { $0.isValid }
        return ref
    }

    /// Unregister a surface when it's being deallocated
    func unregisterSurface(_ ref: Ghostty.SurfaceReference) {
        ref.invalidate()
        activeSurfaces = activeSurfaces.filter { $0.isValid }
        scheduleIdleCleanupIfNeeded()
    }

    /// Reload configuration (call when settings change)
    func reloadConfig() {
        guard let app = self.app else { return }

        guard let config = ghostty_config_new() else {
            Ghostty.logger.error("ghostty_config_new failed during reload")
            return
        }

        loadConfigIntoGhostty(config)
        ghostty_config_finalize(config)
        ghostty_app_update_config(app, config)

        for surfaceRef in activeSurfaces where surfaceRef.isValid {
            ghostty_surface_update_config(surfaceRef.surface, config)
        }

        activeSurfaces = activeSurfaces.filter { $0.isValid }

        ghostty_config_free(config)
        unsetenv("XDG_CONFIG_HOME")
    }

    private func scheduleIdleCleanupIfNeeded() {
        idleCleanupTask?.cancel()
        idleCleanupTask = nil

        guard app != nil, activeSurfaces.isEmpty else { return }

        idleCleanupTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))

            guard let self, self.app != nil, self.activeSurfaces.isEmpty else { return }
            cleanup()
        }
    }
}
