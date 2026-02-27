import Foundation

final class BackendProcess: @unchecked Sendable {
    enum State: Equatable {
        case stopped
        case starting
        case running
        case failed(String)
    }

    private var process: Process?
    private let lock = NSLock()
    private(set) var state: State = .stopped

    private enum BackendProcessError: LocalizedError {
        case projectRootNotFound
        case venvPythonNotFound

        var errorDescription: String? {
            switch self {
            case .projectRootNotFound:
                return "Could not find project root (pyproject.toml and src/main.py not found). Set DICTATION_PROJECT_ROOT or rebuild the app from the repo."
            case .venvPythonNotFound:
                return "Could not find project virtualenv Python (.venv/bin/python). Run ./scripts/dictation.sh setup first."
            }
        }
    }

    static func findProjectRoot() -> URL? {
        if let envRoot = ProcessInfo.processInfo.environment["DICTATION_PROJECT_ROOT"] {
            let url = URL(fileURLWithPath: envRoot)
            if isValidProjectRoot(url) {
                return url
            }
        }

        if let bundleRoot = Bundle.main.object(forInfoDictionaryKey: "DictationProjectRoot") as? String {
            let url = URL(fileURLWithPath: NSString(string: bundleRoot).expandingTildeInPath)
            if isValidProjectRoot(url) {
                return url
            }
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        if isValidProjectRoot(cwd) {
            return cwd
        }

        return nil
    }

    func start() throws {
        lock.lock()
        defer { lock.unlock() }

        guard state != .running && state != .starting else { return }

        guard let root = BackendProcess.findProjectRoot() else {
            state = .failed(BackendProcessError.projectRootNotFound.localizedDescription)
            print("[BackendProcess] \(state)")
            throw BackendProcessError.projectRootNotFound
        }

        guard let backendPython = resolveBackendPython(in: root) else {
            state = .failed(BackendProcessError.venvPythonNotFound.localizedDescription)
            print("[BackendProcess] \(state)")
            throw BackendProcessError.venvPythonNotFound
        }

        let proc = Process()
        proc.executableURL = backendPython
        let host = ProcessInfo.processInfo.environment["DICTATION_ASR_HOST"] ?? "127.0.0.1"
        let port = ProcessInfo.processInfo.environment["DICTATION_ASR_PORT"] ?? "8765"
        proc.arguments = ["-m", "uvicorn", "src.main:app", "--host", host, "--port", port]
        proc.currentDirectoryURL = root
        var env = ProcessInfo.processInfo.environment
        env["DICTATION_PROJECT_ROOT"] = root.path
        proc.environment = env
        proc.terminationHandler = { [weak self] finished in
            guard let self else { return }
            self.lock.lock()
            defer { self.lock.unlock() }

            if finished.terminationStatus == 0 || self.state == .stopped {
                self.state = .stopped
            } else {
                self.state = .failed("Backend exited with code \(finished.terminationStatus)")
                print("[BackendProcess] \(self.state)")
            }
        }

        state = .starting
        do {
            try proc.run()
            process = proc
            state = .running
            print("[BackendProcess] started (pid \(proc.processIdentifier))")
        } catch {
            state = .failed(error.localizedDescription)
            print("[BackendProcess] failed to start: \(error)")
            throw error
        }
    }

    func stop() {
        lock.lock()
        guard let proc = process, proc.isRunning else {
            state = .stopped
            process = nil
            lock.unlock()
            return
        }
        state = .stopped
        lock.unlock()

        print("[BackendProcess] sending SIGTERM (pid \(proc.processIdentifier))")
        proc.terminate()

        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            if proc.isRunning {
                print("[BackendProcess] sending SIGKILL (pid \(proc.processIdentifier))")
                kill(proc.processIdentifier, SIGKILL)
            }
        }

        proc.waitUntilExit()

        lock.lock()
        process = nil
        lock.unlock()
    }

    func restart() throws {
        stop()
        try start()
    }

    private static func isValidProjectRoot(_ url: URL) -> Bool {
        let pyproject = url.appendingPathComponent("pyproject.toml").path
        let backendEntrypoint = url.appendingPathComponent("src/main.py").path
        return FileManager.default.fileExists(atPath: pyproject) && FileManager.default.fileExists(atPath: backendEntrypoint)
    }

    private func resolveBackendPython(in root: URL) -> URL? {
        let candidates = [
            root.appendingPathComponent(".venv/bin/python3"),
            root.appendingPathComponent(".venv/bin/python"),
        ]
        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}
