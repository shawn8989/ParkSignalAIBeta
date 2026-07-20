import Foundation
import Vision
import UIKit
import ImageIO

actor VisionOCRService {

    func recognizeText(in image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw NSError(domain: "VisionOCRService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid image"])
        }

        var recognizedStrings: [String] = []
        let request = VNRecognizeTextRequest { request, _ in
            if let observations = request.results as? [VNRecognizedTextObservation] {
                for obs in observations {
                    if let candidate = obs.topCandidates(1).first {
                        recognizedStrings.append(candidate.string)
                    }
                }
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]

        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        try handler.perform([request])

        let normalized = recognizedStrings
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return normalized
    }
}

private extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default:
            self = .up
        }
    }
}
