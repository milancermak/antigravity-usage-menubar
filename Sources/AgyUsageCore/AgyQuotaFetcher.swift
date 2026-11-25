import Darwin
import Foundation

public enum AgyFetchError: LocalizedError, Equatable, Sendable {
    case binaryNotFound
    case launchFailed(String)
    case timedOut
    case noQuotaData

    public var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "agy CLI not found"
        case .launchFailed(let detail):
            return "Failed to run agy: \(detail)"
        case .timedOut:
            return "Timed out waiting for agy quota"
        case .noQuotaData:
            return "No Gemini quota in agy output"
        }
    }
}

public protocol QuotaFetching: Sendable {
    func fetchQuota(agyPathOverride: String) async throws -> QuotaSnapshot
}

public struct AgyQuotaFetcher: QuotaFetching, Sendable {
    public let timeoutSeconds: TimeInterval

    public init(timeoutSeconds: TimeInterval = 12.0) {
        self.timeoutSeconds = timeoutSeconds
    }

    public static func resolveBinaryPath(override: String = "") -> String? {
        let fm = FileManager.default
        let trimmed = override.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let expanded = (trimmed as NSString).expandingTildeInPath
            if fm.isExecutableFile(atPath: expanded) {
                return expanded
            }
        }

        let home = NSHomeDirectory()
        var candidates = [
            "\(home)/.local/bin/agy",
            "/opt/homebrew/bin/agy",
            "/usr/local/bin/agy",
            "/usr/bin/agy"
        ]

        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":") {
                candidates.append("\(dir)/agy")
            }
        }

        for candidate in candidates where fm.isExecutableFile(atPath: candidate) {
            return candidate
        }

        return nil
    }

    public func fetchQuota(agyPathOverride: String = "") async throws -> QuotaSnapshot {
        guard let binaryPath = Self.resolveBinaryPath(override: agyPathOverride) else {
            throw AgyFetchError.binaryNotFound
        }

        return try await Task.detached(priority: .utility) {
            try runStatusLineProbe(binaryPath: binaryPath, timeout: timeoutSeconds)
        }.value
    }

    private func runStatusLineProbe(binaryPath: String, timeout: TimeInterval) throws -> QuotaSnapshot {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("agy-usage-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer {
            try? fm.removeItem(at: tempDir)
        }

        let outURL = tempDir.appendingPathComponent("out.jsonl")
        let hookURL = tempDir.appendingPathComponent("hook.sh")

        let script = "#!/bin/sh\ncat >> '\(outURL.path)'\nprintf '\\n' >> '\(outURL.path)'\n"
        try script.write(to: hookURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: hookURL.path)

        let settingsObj: [String: Any] = [
            "statusLine": [
                "type": "command",
                "command": hookURL.path,
                "enabled": true,
                "stack_with_default": true
            ]
        ]
        let settingsData = try JSONSerialization.data(withJSONObject: settingsObj)
        guard let settingsJSON = String(data: settingsData, encoding: .utf8) else {
            throw AgyFetchError.launchFailed("Could not serialize settings")
        }

        var masterFD: Int32 = -1
        var slaveFD: Int32 = -1
        guard openpty(&masterFD, &slaveFD, nil, nil, nil) == 0 else {
            throw AgyFetchError.launchFailed("openpty failed")
        }

        let slaveHandle = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: false)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["--settings", settingsJSON]
        process.currentDirectoryURL = tempDir
        process.standardInput = slaveHandle
        process.standardOutput = slaveHandle
        process.standardError = slaveHandle

        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        process.environment = env

        let drainQueue = DispatchQueue(label: "com.agyusagemenubar.pty-drain")

        do {
            try process.run()
        } catch {
            close(slaveFD)
            close(masterFD)
            throw AgyFetchError.launchFailed(error.localizedDescription)
        }

        close(slaveFD)

        let readFD = masterFD
        drainQueue.async {
            var buf = [UInt8](repeating: 0, count: 4096)
            while true {
                let n = read(readFD, &buf, buf.count)
                if n <= 0 { break }
            }
        }

        defer {
            terminate(process)
            close(readFD)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let text = try? String(contentsOf: outURL, encoding: .utf8),
               let snapshot = AgyStatusLineParser.parseLatest(fromNDJSON: text, now: Date()) {
                return snapshot
            }

            if !process.isRunning {
                if let text = try? String(contentsOf: outURL, encoding: .utf8),
                   let snapshot = AgyStatusLineParser.parseLatest(fromNDJSON: text, now: Date()) {
                    return snapshot
                }
                throw AgyFetchError.noQuotaData
            }

            Thread.sleep(forTimeInterval: 0.1)
        }

        throw AgyFetchError.timedOut
    }

    private func terminate(_ process: Process) {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        kill(pid, SIGTERM)

        let waitUntil = Date().addingTimeInterval(1.5)
        while process.isRunning && Date() < waitUntil {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            kill(pid, SIGKILL)
            process.waitUntilExit()
        }
    }
}
