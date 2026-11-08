import Foundation

/// Esecuzione di comandi di sistema di SOLA LETTURA (du, tmutil, fdesetup…).
enum Shell {
    /// Esegue un comando di sola lettura su un thread separato (per non
    /// bloccare quelli di Swift Concurrency) e ne restituisce l'output.
    /// `nil` se il comando fallisce senza produrre nulla.
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
                // `du` esce con errore anche se una sola sottocartella è protetta:
                // teniamo comunque i numeri che ha prodotto.
                continuation.resume(returning: text.isEmpty && process.terminationStatus != 0 ? nil : text)
            }
        }
    }
}
