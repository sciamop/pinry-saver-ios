//
//  ImageClassifier.swift
//  PinryShared
//

import Foundation
import UIKit
@preconcurrency import Vision

class ImageClassifier {
    
    static let shared = ImageClassifier()
    
    private init() {}
    
    /// Classify an image and return relevant tags
    /// - Parameter imageData: The image data to classify
    /// - Returns: Array of classification labels/tags
    func classifyImage(_ imageData: Data) async -> [String] {
        guard let image = UIImage(data: imageData),
              let cgImage = image.cgImage else {
            return []
        }
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNClassifyImageRequest { request, error in
                    guard error == nil,
                          let results = request.results as? [VNClassificationObservation] else {
                        continuation.resume(returning: [])
                        return
                    }
                    
                    // Filter results by confidence threshold and take top tags
                    let tags = results
                        .filter { $0.confidence > 0.1 } // Only include tags with >10% confidence
                        .prefix(10) // Limit to top 10 tags
                        .map { observation in
                            // Clean up the identifier - remove underscores, capitalize properly
                            self.cleanTagIdentifier(observation.identifier)
                        }
                        .filter { !$0.isEmpty } // Remove any empty tags
                    
                    continuation.resume(returning: Array(tags))
                }
                
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    /// Clean up Vision framework identifiers to make them more user-friendly
    /// - Parameter identifier: The raw identifier from Vision (e.g. "golden_retriever_dog")
    /// - Returns: Cleaned tag (e.g. "Golden Retriever")
    private func cleanTagIdentifier(_ identifier: String) -> String {
        // Split by underscores and commas
        let components = identifier.components(separatedBy: CharacterSet(charactersIn: "_,"))
        
        // Capitalize each word and join with spaces
        let cleaned = components
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
        
        return cleaned
    }
}

