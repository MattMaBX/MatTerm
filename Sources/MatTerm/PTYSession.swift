import Darwin
import Foundation
import Combine

@MainActor
final class TerminalSession: ObservableObject, Identifiable {
    let id = UUID()
    let kind: SessionKind

    @Published private(set) var status: SessionStatus = .connecting
    @Published private(set) var title: String
    @Published private(set) var workingDirectory: String
    @Published private(set) var displayRevision: UInt64 = 0
    @Published private(set) var focusRevision = 0
    @Published private(set) var applicationCursorKeys = false
    @Published private(set) var mouseTracking: TerminalMouseTracking = .off
    @Published private(set) var mouseEncoding: TerminalMouseEncoding = .x10
    @Published private(set) var focusReporting = false

    private let terminalEngine: GhosttyTerminalEngine
    private var process: PTYProcess?
    private var hasStarted = false
    private var activeGeneration: UUID?
    private var requestedColumns: UInt16 = 120
    private var requestedRows: UInt16 = 36
    private var colorConfiguration: TerminalColorConfiguration?
    private var pendingOutput = Data()
    private var outputFlushScheduled = false
    private var workingDirectoryTimer: Timer?
    private let outputFlushDelay: TimeInterval = 1.0 / 60.0

    init(kind: SessionKind, scrollbackLineLimit: Int = 240_000) {
        self.kind = kind
        terminalEngine = GhosttyTerminalEngine(columns: requestedColumns, rows: requestedRows)
        workingDirectory = "~"
        title = kind.title
        terminalEngine.configureScrollback(maxLines: scrollbackLineLimit)
    }

    var iconName: String { kind.iconName }
    var columns: UInt16 { requestedColumns }
    var rows: UInt16 { requestedRows }
    var hasScrollback: Bool { terminalEngine.scrollbackRows > 0 }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        let generation = UUID()
        activeGeneration = generation

        let process = PTYProcess(
            kind: kind,
            initialColumns: requestedColumns,
            initialRows: requestedRows
        )
        process.onStart = { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.activeGeneration == generation else { return }
                self.status = .running
                self.refreshWorkingDirectory()
                self.startWorkingDirectoryPolling()
            }
        }
        process.onOutput = { [weak self] data in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.activeGeneration == generation else { return }
                self.enqueueOutput(data, generation: generation)
            }
        }
        process.onExit = { [weak self] exitCode in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.activeGeneration == generation else { return }
                if case .failed = self.status { return }
                self.status = .exited(exitCode)
            }
        }
        process.onFailure = { [weak self] message in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.activeGeneration == generation else { return }
                self.status = .failed(message)
            }
        }
        self.process = process
        process.start()
    }

    func stop() {
        workingDirectoryTimer?.invalidate()
        workingDirectoryTimer = nil
        activeGeneration = nil
        pendingOutput.removeAll(keepingCapacity: true)
        outputFlushScheduled = false
        process?.stop()
        process = nil
    }

    func restart() {
        stop()
        terminalEngine.reset()
        if let colorConfiguration {
            terminalEngine.configureColors(colorConfiguration)
        }
        displayRevision &+= 1
        workingDirectory = "~"
        title = kind.title
        synchronizeTerminalState()
        status = .connecting
        hasStarted = false
        start()
    }

    func send(_ text: String) {
        clearSelection()
        process?.send(text)
    }

    @discardableResult
    func sendKeyEvent(
        keyCode: UInt16,
        modifiers: UInt16,
        optionAsAlt: Bool,
        repeatEvent: Bool = false
    ) -> Bool {
        clearSelection()
        guard let data = encodedKeyEvent(
            keyCode: keyCode,
            modifiers: modifiers,
            optionAsAlt: optionAsAlt,
            repeatEvent: repeatEvent
        ) else { return false }
        process?.send(data)
        return true
    }

    func encodedKeyEvent(
        keyCode: UInt16,
        modifiers: UInt16,
        optionAsAlt: Bool,
        repeatEvent: Bool = false
    ) -> Data? {
        terminalEngine.encodeKey(
            keyCode: keyCode,
            modifiers: modifiers,
            optionAsAlt: optionAsAlt,
            repeatEvent: repeatEvent
        )
    }

    func paste(_ text: String) {
        clearSelection()
        guard let data = terminalEngine.encodePaste(text) else { return }
        process?.send(data)
    }

    @discardableResult
    func setSelection(
        startColumn: Int,
        startRow: Int,
        endColumn: Int,
        endRow: Int,
        rectangle: Bool = false
    ) -> Bool {
        let changed = terminalEngine.setSelection(
            startColumn: startColumn,
            startRow: startRow,
            endColumn: endColumn,
            endRow: endRow,
            rectangle: rectangle
        )
        if changed { displayRevision &+= 1 }
        return changed
    }

    func clearSelection() {
        terminalEngine.clearSelection()
        displayRevision &+= 1
    }

    func selectedText() -> String? {
        terminalEngine.selectedText()
    }

    func requestFocus() {
        focusRevision &+= 1
    }

    func sendFocusEvent(_ focused: Bool) {
        guard terminalEngine.focusReporting else { return }
        guard let data = terminalEngine.encodeFocusEvent(focused: focused) else { return }
        process?.send(data)
    }

    func clearDisplay() {
        terminalEngine.write(Data("\u{1B}[2J\u{1B}[H".utf8))
        displayRevision &+= 1
    }

    func scrollViewport(delta: Int) {
        terminalEngine.scrollViewport(delta: delta)
        displayRevision &+= 1
    }

    func scrollViewport(row: Int) {
        terminalEngine.scrollViewport(row: row)
        displayRevision &+= 1
    }

    func scrollToBottom() {
        terminalEngine.scrollToBottom()
        displayRevision &+= 1
    }

    func resize(columns: UInt16, rows: UInt16) {
        requestedColumns = max(2, columns)
        requestedRows = max(2, rows)
        terminalEngine.resize(columns: requestedColumns, rows: requestedRows)
        synchronizeTerminalState()
        process?.resize(columns: columns, rows: rows)
    }

    func configureColors(_ configuration: TerminalColorConfiguration) {
        guard colorConfiguration?.id != configuration.id else { return }
        colorConfiguration = configuration
        terminalEngine.configureColors(configuration)
        displayRevision &+= 1
    }

    func configureScrollback(maxLines: Int) {
        guard terminalEngine.configureScrollback(maxLines: maxLines) else { return }
        displayRevision &+= 1
    }

    private func receive(_ data: Data) {
        terminalEngine.write(data)
        let responses = terminalEngine.drainPTYOutput()
        if !responses.isEmpty { process?.send(responses) }
        synchronizeTerminalState()
        displayRevision &+= 1
    }

    // Kept for diagnostics and tests without forcing a full String allocation
    // on every PTY output batch.
    var displayText: String { terminalEngine.visibleText }

    // The renderer consumes Ghostty's cell snapshot. A terminal pane must
    // never be laid out as a proportional text paragraph: tmux and full-screen
    // programs address an exact row/column grid.
    var displayGrid: TerminalGridSnapshot { terminalEngine.snapshot() }

    private func startWorkingDirectoryPolling() {
        guard case .local = kind else { return }
        workingDirectoryTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshWorkingDirectory()
            }
        }
        workingDirectoryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func refreshWorkingDirectory() {
        guard case .local = kind, let path = process?.currentWorkingDirectory else { return }
        updateWorkingDirectory(path)
    }

    private func updateWorkingDirectory(_ path: String) {
        let compact = compactPath(path)
        guard !compact.isEmpty, compact != workingDirectory else { return }
        workingDirectory = compact
        updateTitle()
    }

    private func updateTitle() {
        switch kind {
        case .local:
            title = workingDirectory
        case .ssh(let profile):
            title = profile.tabHostName + " " + workingDirectory
        }
    }

    private func compactPath(_ path: String) -> String {
        guard case .local = kind else {
            return path.isEmpty ? "~" : path
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func enqueueOutput(_ data: Data, generation: UUID) {
        guard activeGeneration == generation else { return }
        if !data.isEmpty {
            pendingOutput.append(data)
        }
        guard !outputFlushScheduled else { return }
        outputFlushScheduled = true

        DispatchQueue.main.asyncAfter(deadline: .now() + outputFlushDelay) { [weak self] in
            guard let self else { return }
            self.outputFlushScheduled = false
            guard self.activeGeneration == generation else { return }
            guard !self.pendingOutput.isEmpty else { return }
            let data = self.pendingOutput
            self.pendingOutput = Data()
            self.receive(data)

            if !self.pendingOutput.isEmpty {
                self.enqueueOutput(Data(), generation: generation)
            }
        }
    }

    private func synchronizeTerminalState() {
        applicationCursorKeys = terminalEngine.applicationCursorKeys
        mouseTracking = terminalEngine.mouseTracking
        mouseEncoding = terminalEngine.mouseEncoding
        focusReporting = terminalEngine.focusReporting

        if case .local = kind, let path = terminalEngine.workingDirectory {
            let decodedPath: String
            if let url = URL(string: path), url.scheme == "file" {
                decodedPath = url.path.removingPercentEncoding ?? url.path
            } else {
                decodedPath = path.removingPercentEncoding ?? path
            }
            if !decodedPath.isEmpty { updateWorkingDirectory(decodedPath) }
        }
    }

    func sendMouse(
        kind: TerminalMouseEventKind,
        button: Int = -1,
        column: Int,
        row: Int,
        modifiers: Int = 0,
        anyButtonPressed: Bool = false
    ) {
        guard mouseTracking != .off else { return }
        let clampedColumn = max(1, column)
        let clampedRow = max(1, row)
        guard let data = terminalEngine.encodeMouse(
            kind: kind,
            button: button,
            column: clampedColumn,
            row: clampedRow,
            modifiers: UInt16(clamping: modifiers),
            anyButtonPressed: anyButtonPressed
        ) else { return }
        process?.send(data)
    }
}

private final class PTYProcess: @unchecked Sendable {
    private let kind: SessionKind
    private let initialColumns: UInt16
    private let initialRows: UInt16
    private var masterFileDescriptor: Int32 = -1
    private var childProcessID: pid_t = -1
    private let ioQueue = DispatchQueue(label: "com.matterm.pty.io", qos: .userInitiated)
    private let writeQueue = DispatchQueue(label: "com.matterm.pty.write", qos: .userInitiated)
    private let waitQueue = DispatchQueue(label: "com.matterm.pty.wait", qos: .utility)
    private let lock = NSLock()

    var onStart: (() -> Void)?
    var onOutput: ((Data) -> Void)?
    var onExit: ((Int32) -> Void)?
    var onFailure: ((String) -> Void)?

    var currentWorkingDirectory: String? {
        lock.lock()
        let pid = childProcessID
        lock.unlock()
        guard pid > 0 else { return nil }

        var info = proc_vnodepathinfo()
        let result = proc_pidinfo(
            pid,
            PROC_PIDVNODEPATHINFO,
            0,
            &info,
            Int32(MemoryLayout<proc_vnodepathinfo>.size)
        )
        guard result == MemoryLayout<proc_vnodepathinfo>.size else { return nil }
        return withUnsafePointer(to: &info.pvi_cdir.vip_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }
    }

    init(kind: SessionKind, initialColumns: UInt16 = 120, initialRows: UInt16 = 36) {
        self.kind = kind
        self.initialColumns = max(2, initialColumns)
        self.initialRows = max(2, initialRows)
    }

    func start() {
        var size = winsize(
            ws_row: initialRows,
            ws_col: initialColumns,
            ws_xpixel: 0,
            ws_ypixel: 0
        )

        var arguments: [String]
        var executablePath: String
        switch kind {
        case .local:
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            executablePath = shell
            arguments = [shell, "-l"]
        case .ssh(let profile):
            executablePath = "/usr/bin/ssh"
            arguments = makeSSHArguments(profile)
        }

        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["TERM_PROGRAM"] = "MatTerm"

        // Resolve the local starting directory before fork. Calling Foundation APIs
        // in the child can inherit locks from other app threads and prevent exec.
        let startingDirectory = {
            if case .local = kind {
                return strdup(FileManager.default.homeDirectoryForCurrentUser.path)
            }
            return nil
        }()

        var argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) }
        argv.append(nil)
        var envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") }
        envp.append(nil)
        let executable = strdup(executablePath)

        var master: Int32 = -1
        let child = forkpty(&master, nil, nil, &size)
        guard child >= 0 else {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
            free(executable)
            free(startingDirectory)
            onFailure?(String(cString: strerror(errno)))
            return
        }

        if child == 0 {
            // forkpty gives the shell a controlling terminal before exec.
            if let startingDirectory {
                _ = Darwin.chdir(startingDirectory)
            }
            let execResult: Int32 = argv.withUnsafeMutableBufferPointer { argvBuffer in
                envp.withUnsafeMutableBufferPointer { envpBuffer in
                    execve(executable, argvBuffer.baseAddress!, envpBuffer.baseAddress!)
                }
            }
            _exit(execResult == -1 ? 127 : Int32(execResult))
        }

        argv.forEach { free($0) }
        envp.forEach { free($0) }
        free(executable)
        free(startingDirectory)
        masterFileDescriptor = master
        childProcessID = child

        onStart?()
        ioQueue.async(execute: DispatchWorkItem { [weak self] in
            self?.readLoop()
        })
        waitQueue.async(execute: DispatchWorkItem { [weak self] in
            guard let self else { return }
            var status: Int32 = 0
            waitpid(child, &status, 0)
            let exitedNormally = (status & 0x7F) == 0
            let exitCode = exitedNormally ? ((status >> 8) & 0xFF) : 128 + (status & 0x7F)
            DispatchQueue.main.async {
                self.onExit?(Int32(exitCode))
            }
        })
    }

    func send(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        send(data)
    }

    func send(_ data: Data) {
        writeQueue.async { [weak self] in
            self?.writeData(data)
        }
    }

    func resize(columns: UInt16, rows: UInt16) {
        lock.lock()
        defer { lock.unlock() }
        guard masterFileDescriptor >= 0 else { return }
        var size = winsize(ws_row: rows, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(masterFileDescriptor, TIOCSWINSZ, &size)
    }

    func stop() {
        lock.lock()
        let fd = masterFileDescriptor
        let pid = childProcessID
        masterFileDescriptor = -1
        childProcessID = -1
        lock.unlock()

        if pid > 0 {
            kill(pid, SIGHUP)
        }
        if fd >= 0 {
            close(fd)
        }
    }

    private func readLoop() {
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            lock.lock()
            let fd = masterFileDescriptor
            lock.unlock()
            guard fd >= 0 else { return }

            let count = buffer.withUnsafeMutableBytes { bytes in
                read(fd, bytes.baseAddress, bytes.count)
            }
            if count > 0 {
                onOutput?(Data(buffer[0..<count]))
                continue
            }
            if count < 0 && errno == EINTR { continue }
            return
        }
    }

    private func writeData(_ data: Data) {
        lock.lock()
        let fd = masterFileDescriptor
        lock.unlock()
        guard fd >= 0 else { return }

        data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var remaining = bytes.count
            var pointer = baseAddress
            while remaining > 0 {
                let written = write(fd, pointer, remaining)
                if written > 0 {
                    remaining -= written
                    pointer = pointer.advanced(by: written)
                    continue
                }
                if written < 0 && errno == EINTR { continue }
                return
            }
        }
    }
}

private func makeSSHArguments(_ profile: SSHProfile) -> [String] {
    var arguments = ["ssh", "-tt"]
    if profile.port != 22 {
        arguments.append(contentsOf: ["-p", String(profile.port)])
    }
    if !profile.identityPath.isEmpty {
        arguments.append(contentsOf: ["-i", NSString(string: profile.identityPath).expandingTildeInPath])
    }
    arguments.append(profile.target)
    return arguments
}
