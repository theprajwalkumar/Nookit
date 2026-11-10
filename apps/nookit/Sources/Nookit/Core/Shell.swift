import Foundation

struct ShellResult: Sendable {
    let stdout: String
    let stderr: String
    let status: Int32

    var succeeded: Bool { status == 0 }
    var output: String { stdout.isEmpty ? stderr : stdout }
}

enum ShellError: LocalizedError {
    case launchFailed(String)
    case failed(status: Int32, message: String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            return "Couldn’t start the helper process. \(message)"
        case .failed(let status, let message):
            let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "The command failed (exit \(status))." : detail
        case .timedOut:
            return "The command took too long and was stopped."
        }
    }
}

enum Shell {
    @discardableResult
    static func run(
        _ executable: String,
        _ arguments: [String] = [],
        workingDirectory: URL? = nil,
        input: Data? = nil,
        environment: [String: String]? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let workingDirectory { process.currentDirectoryURL = workingDirectory }
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        if let input {
            let inPipe = Pipe()
            process.standardInput = inPipe
            // Feed after launch below.
            _ = inPipe
        } else {
            process.standardInput = FileHandle.nullDevice
        }

        do {
            try process.run()
        } catch {
            throw ShellError.launchFailed(error.localizedDescription)
        }

        if let input, let inPipe = process.standardInput as? Pipe {
            inPipe.fileHandleForWriting.write(input)
            try? inPipe.fileHandleForWriting.close()
        }

        if let timeout {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                if process.isRunning { process.terminate() }
            }
        }

        async let outData = readAll(outPipe.fileHandleForReading)
        async let errData = readAll(errPipe.fileHandleForReading)

        process.waitUntilExit()

        let out = await outData
        let err = await errData
        let stdout = String(data: out, encoding: .utf8) ?? ""
        let stderr = String(data: err, encoding: .utf8) ?? ""
        return ShellResult(stdout: stdout, stderr: stderr, status: process.terminationStatus)
    }

    /// Runs and throws with stderr when the exit status is non-zero.
    static func checked(
        _ executable: String,
        _ arguments: [String] = [],
        workingDirectory: URL? = nil,
        input: Data? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> String {
        let result = try await run(executable, arguments, workingDirectory: workingDirectory, input: input, timeout: timeout)
        guard result.succeeded else {
            throw ShellError.failed(status: result.status, message: result.stderr.isEmpty ? result.stdout : result.stderr)
        }
        return result.stdout
    }

    static func which(_ tool: String) -> String? {
        let paths = [
            "/usr/bin/\(tool)", "/usr/local/bin/\(tool)", "/opt/homebrew/bin/\(tool)",
            "/opt/local/bin/\(tool)", "/bin/\(tool)", "/usr/sbin/\(tool)"
        ]
        for path in paths where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        if let envPath = ProcessInfo.processInfo.environment["PATH"] {
            for dir in envPath.split(separator: ":") {
                let candidate = String(dir) + "/" + tool
                if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
            }
        }
        return nil
    }

    private static func readAll(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let data = handle.readDataToEndOfFile()
                continuation.resume(returning: data)
            }
        }
    }
}

enum AppPaths {
    static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("Nookit", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func supportFile(_ name: String) -> URL {
        support.appendingPathComponent(name)
    }

    static func supportFolder(_ name: String) -> URL {
        let dir = support.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
