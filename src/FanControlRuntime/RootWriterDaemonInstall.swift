import Foundation

package struct RootWriterDaemonStatus {
    package let installedBinaryExists: Bool
    package let launchDaemonPlistExists: Bool
    package let socketExists: Bool
    package let connectionMessage: String
}

package struct RootWriterDaemonInstaller {
    private let cliExecutablePath: String
    private let fileManager = FileManager.default

    package init(cliExecutablePath: String) {
        self.cliExecutablePath = cliExecutablePath
    }

    package func install() throws {
        guard geteuid() == 0 else {
            throw RuntimeCommandError("daemon install requires root privileges; rerun with sudo")
        }

        let sourceURL = URL(fileURLWithPath: siblingDaemonBinaryPath())
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw RuntimeCommandError("expected daemon binary next to CLI at \(sourceURL.path); build the package first")
        }

        try fileManager.createDirectory(
            at: URL(fileURLWithPath: RootWriterDaemonPaths.installDirectory, isDirectory: true),
            withIntermediateDirectories: true
        )

        let installURL = URL(fileURLWithPath: RootWriterDaemonPaths.executablePath)
        if fileManager.fileExists(atPath: installURL.path) {
            try fileManager.removeItem(at: installURL)
        }
        try fileManager.copyItem(at: sourceURL, to: installURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installURL.path)

        let plistData = try launchDaemonPlist().data(using: .utf8).unwrap(or: RuntimeCommandError("failed to encode launchd plist"))
        fileManager.createFile(atPath: RootWriterDaemonPaths.launchDaemonPlistPath, contents: plistData)
        try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: RootWriterDaemonPaths.launchDaemonPlistPath)

        try runLaunchctl(arguments: ["bootout", "system/\(RootWriterDaemonPaths.launchDaemonLabel)"], allowFailure: true)
        try runLaunchctl(arguments: ["bootstrap", "system", RootWriterDaemonPaths.launchDaemonPlistPath])
        try runLaunchctl(arguments: ["kickstart", "-k", "system/\(RootWriterDaemonPaths.launchDaemonLabel)"])
    }

    package func remove() throws {
        guard geteuid() == 0 else {
            throw RuntimeCommandError("daemon remove requires root privileges; rerun with sudo")
        }

        try runLaunchctl(arguments: ["bootout", "system/\(RootWriterDaemonPaths.launchDaemonLabel)"], allowFailure: true)
        try? fileManager.removeItem(atPath: RootWriterDaemonPaths.launchDaemonPlistPath)
        try? fileManager.removeItem(atPath: RootWriterDaemonPaths.executablePath)
        try? fileManager.removeItem(atPath: RootWriterDaemonPaths.socketPath)
    }

    package func status() -> RootWriterDaemonStatus {
        let installedBinaryExists = fileManager.fileExists(atPath: RootWriterDaemonPaths.executablePath)
        let launchDaemonPlistExists = fileManager.fileExists(atPath: RootWriterDaemonPaths.launchDaemonPlistPath)
        let socketExists = fileManager.fileExists(atPath: RootWriterDaemonPaths.socketPath)

        let connectionMessage: String
        do {
            let client = try DaemonFanWriterClient.connect()
            defer { try? client.shutdown() }
            let fans = try client.inspectFans()
            connectionMessage = "connected successfully; daemon reported \(fans.count) fan(s)"
        } catch {
            connectionMessage = error.localizedDescription
        }

        return RootWriterDaemonStatus(
            installedBinaryExists: installedBinaryExists,
            launchDaemonPlistExists: launchDaemonPlistExists,
            socketExists: socketExists,
            connectionMessage: connectionMessage
        )
    }

    private func siblingDaemonBinaryPath() -> String {
        let cliURL = URL(fileURLWithPath: cliExecutablePath).resolvingSymlinksInPath()
        return cliURL.deletingLastPathComponent().appendingPathComponent("root-writer-daemon").path
    }

    private func launchDaemonPlist() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(RootWriterDaemonPaths.launchDaemonLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(RootWriterDaemonPaths.executablePath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>Umask</key>
            <integer>7</integer>
            <key>StandardOutPath</key>
            <string>/var/log/macs-fan-control-root-writer.log</string>
            <key>StandardErrorPath</key>
            <string>/var/log/macs-fan-control-root-writer.log</string>
        </dict>
        </plist>
        """
    }

    private func runLaunchctl(arguments: [String], allowFailure: Bool = false) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        guard allowFailure || process.terminationStatus == 0 else {
            let message = String(data: (try? stderr.fileHandleForReading.readToEnd()) ?? Data(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "launchctl failed"
            throw RuntimeCommandError(message)
        }
    }
}

private extension Optional {
    func unwrap(or error: @autoclosure () -> Error) throws -> Wrapped {
        guard let value = self else {
            throw error()
        }
        return value
    }
}
