import CoreGraphics
import Foundation
import ImageIO
import Vision

public enum TextRecognizer {
    public static func prewarm() {
        DispatchQueue.global(qos: .utility).async {
            guard let context = CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue),
                  let image = { context.setFillColor(gray: 1, alpha: 1)
                                context.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
                                return context.makeImage() }() else { return }
            let request = makeRequest()
            try? VNImageRequestHandler(cgImage: image).perform([request])
        }
    }

    static func makeRequest() -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate

        request.recognitionLanguages = Array(Set([L.current.locale.replacingOccurrences(of: "_", with: "-"), "en-US"]))
        request.usesLanguageCorrection = true
        return request
    }

    public static func text(inImageAt url: URL) async throws -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw AIError(L.t("error.image.cantOpen"))
        }
        return try await text(in: image)
    }

    public static func text(inImageData data: Data) async throws -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw AIError(L.t("error.image.cantOpen"))
        }
        return try await text(in: image)
    }

    public static func text(in image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = makeRequest()
                do {
                    try VNImageRequestHandler(cgImage: image).perform([request])
                    let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                    continuation.resume(returning: lines.joined(separator: "\n"))
                } catch {
                    continuation.resume(throwing: AIError(L.t("error.image.cantRead")))
                }
            }
        }
    }
}
