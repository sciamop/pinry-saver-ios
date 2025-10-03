//
//  PinryUploader.swift
//  PinryShared
//

import Foundation
import UIKit

enum PinryUploadError: Error {
    case invalidSettings
    case noAPIToken
    case encodingFailed
    case networkError(Error)
    case invalidResponse
    case httpError(Int)
}

struct PinryUploadResult {
    let success: Bool
    let message: String
}

struct PinryPin {
    let imageData: Data
    let description: String
    let source: String
    let boardID: String
}

class PinryUploader {
    
    static let shared = PinryUploader()
    
    private init() {}
    
    // MARK: - API Configuration
    
    private var baseURL: String {
        return PinrySettings.load().pinryBaseURL
    }
    
    private var apiToken: String? {
        return KeychainStore.retrieveAPIToken()
    }
    
    private var defaultBoardID: String {
        return PinrySettings.load().defaultBoardID
    }
    
    // MARK: - Upload Method
    
    func upload(_ pin: PinryPin) async -> PinryUploadResult {
        // Validate settings
        guard !baseURL.isEmpty else {
            return PinryUploadResult(success: false, message: "Pinry Base URL is not configured")
        }
        
        guard let apiToken = apiToken, !apiToken.isEmpty else {
            return PinryUploadResult(success: false, message: "API Token is not configured")
        }
        
        guard !defaultBoardID.isEmpty else {
            return PinryUploadResult(success: false, message: "Default Board ID is not configured")
        }
        
        // Build URL
        guard let url = URL(string: "\(baseURL)/api/pins/") else {
            return PinryUploadResult(success: false, message: "Invalid Pinry Base URL")
        }
        
        // Convert HEIC to JPEG if needed
        let processedImageData: Data
        do {
            processedImageData = try convertToJPEGIfNeeded(pin.imageData)
        } catch {
            return PinryUploadResult(success: false, message: "Failed to process image: \(error.localizedDescription)")
        }
        
        // Create multipart request
        let request: URLRequest
        do {
            request = try createMultipartRequest(
                url: url,
                apiToken: apiToken,
                imageData: processedImageData,
                description: pin.description,
                source: pin.source,
                boardID: pin.boardID.isEmpty ? defaultBoardID : pin.boardID
            )
        } catch {
            return PinryUploadResult(success: false, message: "Failed to create request: \(error.localizedDescription)")
        }
        
        // Perform upload
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                    return PinryUploadResult(success: true, message: "Pin saved successfully!")
                } else {
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                    return PinryUploadResult(success: false, message: "Server error (\(httpResponse.statusCode)): \(errorMessage)")
                }
            } else {
                return PinryUploadResult(success: false, message: "Invalid response from server")
            }
        } catch {
            return PinryUploadResult(success: false, message: "Network error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Helper Methods
    
    private func convertToJPEGIfNeeded(_ imageData: Data) throws -> Data {
        guard let image = UIImage(data: imageData),
              let inputImageFormat = imageData.imageFormat else {
            return imageData // Return original if we can't determine format
        }
        
        // Only convert HEIC to JPEG
        if inputImageFormat == .heic {
            guard let jpegData = image.jpegData(compressionQuality: 0.9) else {
                throw PinryUploadError.encodingFailed
            }
            return jpegData
        }
        
        return imageData
    }
    
    private func createMultipartRequest(
        url: URL,
        apiToken: String,
        imageData: Data,
        description: String,
        source: String,
        boardID: String
    ) throws -> URLRequest {
        
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Token \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add image field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add description field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"description\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(description)\r\n".data(using: .utf8)!)
        
        // Add source field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"source\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(source)\r\n".data(using: .utf8)!)
        
        // Add board field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"board\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(boardID)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        return request
    }
}

// MARK: - Image Format Detection

enum ImageFormat {
    case jpeg
    case heic
    case unknown
}

extension Data {
    var imageFormat: ImageFormat? {
        guard count >= 4 else { return nil }
        
        // Check JPEG signature (FF D8 FF)
        if self[0] == 0xFF && self[1] == 0xD8 && self[2] == 0xFF {
            return .jpeg
        }
        
        // Check HEIC signature - look for 'ftyp' at specific offsets
        if count >= 12 {
            let ftypSignature = "ftyp"
            let dataString = String(data: self[4...7], encoding: .ascii)
            if dataString == ftypSignature {
                let brandString = String(data: self[8...11], encoding: .ascii)
                if brandString?.hasPrefix("heic") == true || brandString?.hasPrefix("mif1") == true {
                    return .heic
                }
            }
        }
        
        return .unknown
    }
}
