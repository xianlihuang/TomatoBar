import Foundation

protocol TBLogEvent: Encodable {
    var type: String { get }
    var timestamp: Date { get }
}

final class TBLogEventAppStart: TBLogEvent {
    let type = "appstart"
    let timestamp = Date()
}

final class TBLogEventTransition: TBLogEvent {
    let type = "transition"
    let timestamp = Date()

    private let event: String
    private let fromState: String
    private let toState: String

    init(fromContext context: TBStateMachine.Context) {
        event = context.event.map { "\($0)" } ?? "none"
        fromState = "\(context.fromState)"
        toState = "\(context.toState)"
    }
}

private let logFileName = "TomatoBar.log"
private let lineEnd = Data([0x0A])
private let maximumLogSize: UInt64 = 5 * 1024 * 1024

let logger = TBLogger()

final class TBLogger {
    private let logHandle: FileHandle?
    private let encoder = JSONEncoder()

    init() {
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .secondsSince1970

        let fileManager = FileManager.default
        guard let cachesDirectory = fileManager
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first
        else {
            print("cannot locate caches directory")
            logHandle = nil
            return
        }

        let logURL = cachesDirectory.appendingPathComponent(logFileName)
        let path = logURL.path

        // Keep the event log from growing without bound. One rotated file is
        // enough for the productivity analysis use case described in README.
        if let attributes = try? fileManager.attributesOfItem(atPath: path),
           let size = (attributes[.size] as? NSNumber)?.uint64Value,
           size > maximumLogSize
        {
            let backupURL = logURL.appendingPathExtension("1")
            try? fileManager.removeItem(at: backupURL)
            try? fileManager.moveItem(at: logURL, to: backupURL)
        }

        if !fileManager.fileExists(atPath: path),
           !fileManager.createFile(atPath: path, contents: nil)
        {
            print("cannot create log file")
            logHandle = nil
            return
        }

        guard let handle = FileHandle(forWritingAtPath: path) else {
            print("cannot open log file")
            logHandle = nil
            return
        }

        do {
            try handle.seekToEnd()
        } catch {
            print("cannot seek to end of log file: \(error)")
        }

        logHandle = handle
    }

    deinit {
        try? logHandle?.close()
    }

    func append(event: TBLogEvent) {
        guard let logHandle else {
            return
        }

        do {
            let jsonData = try encoder.encode(event)
            try logHandle.seekToEnd()
            try logHandle.write(contentsOf: jsonData + lineEnd)
            try logHandle.synchronize()
        } catch {
            print("cannot write to log file: \(error)")
        }
    }
}
