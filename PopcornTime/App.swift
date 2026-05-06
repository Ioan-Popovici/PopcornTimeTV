//
//  PopcornTimetvOS_SwiftUIApp.swift
//  PopcornTimetvOS SwiftUI
//
//  Created by Alexandru Tudose on 19.06.2021.
//  Copyright © 2021 PopcornTime. All rights reserved.
//

import SwiftUI
import PopcornTorrent
import os.log


@main
struct PopcornTime: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        CrashReporter.install()
        #if os(macOS)
        // Resolve the user's storage-path bookmarks before any streamer
        // is constructed (the bootstrap below kicks PTTorrentsSession
        // five seconds in). Idempotent and cheap when no override is set.
        Session.applyStorageOverrides()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                TabBarView()
                    .modifier(AcceptTermsOfService())
                #if os(iOS) || os(macOS)
                    .modifier(MagnetTorrentLinkOpener())
                #elseif os(tvOS)
                    .modifier(TopShelfLinkOpener())
                #endif
                    .onAppear {
                        // bootstrap torrent session
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            PTTorrentsSession.shared()
                            // The recently-played warmer is currently
                            // disabled — see the docstring on
                            // `TorrentSessionWarmer`. It crashed
                            // libtorrent's auto-manager (SEGV in
                            // `is_inactive`) and starved fresh play
                            // streamers of their first-frame pieces by
                            // monopolising download bandwidth on
                            // unrelated pieces. The recording side
                            // (`Session.recordRecentlyPlayed`) stays
                            // active so the LRU is ready when we
                            // re-introduce a safer warm strategy.
                            //
                            // TorrentSessionWarmer.shared.warmAllRecentlyPlayed()
                        }
                    }
                    .onChange(of: scenePhase) { _, newPhase in
                        // "Clear Cache Upon Exit" semantics: wipe the
                        // streaming cache when the scene leaves the
                        // foreground. macOS additionally hooks
                        // `applicationWillTerminate` for the
                        // proper-quit case (see AppDelegate). Player
                        // exit no longer deletes anything, so partial
                        // downloads survive across player sessions
                        // for instant seek-back and re-watch.
                        if newPhase == .background, Session.removeCacheOnPlayerExit {
                            var cleaner = ClearCache()
                            cleaner.emptyCache()
                        }
                    }
            }
            .preferredColorScheme(.dark)
            #if os(iOS)
            .accentColor(.white)
            .modifier(SecondaryScreen())
            #endif
        }
//        #if os(iOS) || os(macOS)
//        .commands(content: {
//            OpenCommand()
//        })
//        #endif
        
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
//        .windowToolbarStyle(.expanded)
        #endif
        
        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif

    }

// in order do exit app on window close
#if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    var appDelegate

    final class AppDelegate: NSObject, NSApplicationDelegate {
        func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
            true
        }

        @MainActor
        func applicationWillTerminate(_ notification: Notification) {
            // Definitive app-quit cache wipe when the user has opted
            // in. The scenePhase `.background` handler covers most
            // cases; this catches the macOS Cmd-Q path where the
            // window closes and termination follows immediately
            // without an intermediate background phase.
            guard Session.removeCacheOnPlayerExit else { return }
            var cleaner = ClearCache()
            cleaner.emptyCache()
        }
    }
#endif
}


// MARK: - Crash reporting

/// Catches Obj-C uncaught exceptions and POSIX signals, dumps a stack
/// trace + diagnostic context to ~/Library/Application Support/PopcornTime/
/// crashes/, and surfaces it on the next launch (logged via os.log
/// *and* printed to stderr so the user sees it in Console.app).
enum CrashReporter {
    private static let logger = Logger(subsystem: "swiftui.PopcornTime", category: "crash")

    /// Install handlers and surface any crash from the previous run.
    /// Call once, as early as possible (before SwiftUI sets up).
    static func install() {
        surfacePendingCrashLogs()

        NSSetUncaughtExceptionHandler { exception in
            CrashReporter.write(
                kind: "uncaught Obj-C exception",
                reason: "\(exception.name.rawValue): \(exception.reason ?? "")",
                callStack: exception.callStackSymbols
            )
        }

        // Catch the signals that typically crash a Cocoa app: aborts, bad
        // memory access, illegal instruction, breakpoints (Swift 6 isolation
        // traps), arithmetic, and pipe.
        let signals: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGFPE, SIGPIPE]
        for sig in signals {
            signal(sig) { signal in
                let name = String(cString: strsignal(signal))
                let stack = Thread.callStackSymbols
                CrashReporter.write(
                    kind: "POSIX signal",
                    reason: "\(name) (\(signal))",
                    callStack: stack
                )
                // Re-raise the default handler so the OS still records its
                // own .ips report and the process actually terminates.
                Foundation.signal(signal, SIG_DFL)
                raise(signal)
            }
        }
    }

    static var crashFolder: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support
            .appendingPathComponent("PopcornTime", isDirectory: true)
            .appendingPathComponent("crashes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Async-signal-safe write via low-level POSIX `write(2)`.
    private static func write(kind: String, reason: String, callStack: [String]) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let path = crashFolder.appendingPathComponent("crash-\(timestamp).log").path

        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString

        var report = """
        =============================================================
        PopcornTime — \(kind)
        =============================================================
        Date     : \(timestamp)
        Version  : \(version) (\(build))
        OS       : \(os)
        PID      : \(ProcessInfo.processInfo.processIdentifier)
        Reason   : \(reason)

        Call stack:
        """
        for (i, frame) in callStack.enumerated() {
            report += "\n\(String(format: "%2d", i))  \(frame)"
        }
        report += "\n"

        let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        guard fd >= 0 else { return }
        report.withCString { ptr in
            _ = Foundation.write(fd, ptr, strlen(ptr))
        }
        close(fd)
    }

    /// Find any crash logs from previous runs, emit them to the unified
    /// log + stderr, then archive them under `seen/` so future launches
    /// don't duplicate.
    static func surfacePendingCrashLogs() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: crashFolder,
            includingPropertiesForKeys: nil
        ) else { return }
        let logs = files.filter { $0.pathExtension == "log" }
        guard !logs.isEmpty else { return }

        let seen = crashFolder.appendingPathComponent("seen", isDirectory: true)
        try? FileManager.default.createDirectory(at: seen, withIntermediateDirectories: true)

        for url in logs {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                logger.error("Previous crash:\n\(text, privacy: .public)")
                FileHandle.standardError.write(Data("\n\(text)\n".utf8))
            }
            try? FileManager.default.moveItem(
                at: url,
                to: seen.appendingPathComponent(url.lastPathComponent)
            )
        }
    }
}
