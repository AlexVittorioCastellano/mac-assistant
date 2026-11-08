import Foundation

enum Shell {
    static func run(_ tool: String, _ arguments: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: tool)
                process.arguments = arguments
                process.environment = ["LC_ALL": "C"]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                do { try process.run() } catch { continuation.resume(returning: nil); return }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let text = String(decoding: data, as: UTF8.self)

                continuation.resume(returning: text.isEmpty && process.terminationStatus != 0 ? nil : text)
            }
        }
    }
}
