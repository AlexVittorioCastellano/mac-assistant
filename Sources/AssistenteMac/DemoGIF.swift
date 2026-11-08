import AppKit
import AssistenteCore
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum DemoGIF {
    static let size = CGSize(width: 400, height: 720)

    static func runIfRequested() {
        guard let folder = ProcessInfo.processInfo.environment["ASSISTENTE_GIF"] else { return }
        Task {
            try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            for code in ["en", "it"] {
                L.override = code
                let frames = await makeFrames()
                write(frames, to: "\(folder)/demo-\(code).gif")
            }
            exit(0)
        }
    }

    static func makeFrames() async -> [(CGImage, Double)] {
        var frames: [(CGImage, Double)] = []
        func snap(_ m: AssistantViewModel, _ seconds: Double) {
            if let image = image(of: m) { frames.append((image, seconds)) }
        }
        func scenario(_ name: String) -> (@MainActor (AssistantViewModel) async -> Void)? {
            DemoScreenshots.scenarios.first { $0.0 == name }?.1
        }

        let idle = AssistantViewModel()
        snap(idle, 1.4)

        for (name, question, label) in [("controllo", Assistant.healthQuestion, L.t("ui.working.check")),
                                         ("spazio", Assistant.diskQuestion, L.t("ui.working.check")),
                                         ("messaggio", Assistant.messageQuestion, L.t("ui.working.message"))] {
            let m = AssistantViewModel()
            m.question = question
            m.workingLabel = label
            m.isWorking = true
            snap(m, 0.9)
            await scenario(name)?(m)
            m.isWorking = false
            let full = m.answer
            if !full.isEmpty {
                for share in [0.3, 0.65] {
                    m.answer = prefix(full, share)
                    snap(m, 0.35)
                }
                m.answer = full
            }
            snap(m, 3.0)
        }

        let chat = AssistantViewModel()
        await scenario("chat")?(chat)
        if chat.messages.count == 2 {
            let full = chat.messages[1].text
            let guided = chat.messages[1].basedOnGuide
            chat.messages[1] = ChatMessage(role: .assistant, text: "", basedOnGuide: guided)
            snap(chat, 0.8)
            for share in [0.35, 0.7] {
                chat.messages[1] = ChatMessage(role: .assistant, text: prefix(full, share), basedOnGuide: guided)
                snap(chat, 0.35)
            }
            chat.messages[1] = ChatMessage(role: .assistant, text: full, basedOnGuide: guided)
            snap(chat, 3.2)
        }
        return frames
    }

    static func prefix(_ text: String, _ share: Double) -> String {
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        return words.prefix(max(1, Int(Double(words.count) * share))).joined(separator: " ")
    }

    static func image(of model: AssistantViewModel) -> CGImage? {
        let root = ContentView(model: model)
            .padding(.top, 6)
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .light)
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        let scale: CGFloat = 2
        guard let full = rep.cgImage,
              let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(full, in: CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale))
        return context.makeImage()
    }

    static func write(_ frames: [(CGImage, Double)], to path: String) {
        guard let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                                                UTType.gif.identifier as CFString, frames.count, nil)
        else { return }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for (image, seconds) in frames {
            CGImageDestinationAddImage(destination, image,
                                       [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: seconds]] as CFDictionary)
        }
        CGImageDestinationFinalize(destination)
    }
}
