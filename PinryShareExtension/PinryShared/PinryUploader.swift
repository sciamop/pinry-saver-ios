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
    let imageData: Data?  // Optional - nil for URL-only pins
    let url: String?      // Optional - for URL-based pins
    let description: String
    let source: String
    let boardID: String
    
    // Convenience initializer for image-based pins
    init(imageData: Data, description: String, source: String, boardID: String) {
        self.imageData = imageData
        self.url = nil
        self.description = description
        self.source = source
        self.boardID = boardID
    }
    
    // Convenience initializer for URL-based pins
    init(url: URL, description: String, source: String, boardID: String) {
        self.imageData = nil
        self.url = url.absoluteString
        self.description = description
        self.source = source
        self.boardID = boardID
    }
}

class PinryUploader {
    
    static let shared = PinryUploader()
    
    private init() {}
    
    // MARK: - API Configuration
    
    private var baseURL: String {
        return PinrySettings.load().pinryBaseURL
    }
    
    private var apiToken: String? {
        let settings = PinrySettings.load()
        return settings.apiToken.isEmpty ? nil : settings.apiToken
    }
    
    private var defaultBoardID: String {
        return PinrySettings.load().defaultBoardID
    }
    
    // MARK: - Upload Method
    
    func upload(_ pin: PinryPin) async -> PinryUploadResult {
        NSLog("🔥 PinryUploader: Starting upload...")
        NSLog("🔥 PinryUploader: Base URL = '\(baseURL)'")
        NSLog("🔥 PinryUploader: API Token = '\(apiToken ?? "nil")' (\(apiToken?.count ?? 0) chars)")
        NSLog("🔥 PinryUploader: Default Board ID = '\(defaultBoardID)'")
        NSLog("🔥 PinryUploader: Pin URL = '\(pin.url ?? "nil")'")
        NSLog("🔥 PinryUploader: Pin has imageData = \(pin.imageData != nil)")
        
        // Validate settings
        guard !baseURL.isEmpty else {
            NSLog("❌ PinryUploader: Base URL is empty")
            return PinryUploadResult(success: false, message: "Pinry Base URL is not configured")
        }
        
        guard let apiToken = apiToken, !apiToken.isEmpty else {
            NSLog("❌ PinryUploader: API Token is empty or nil")
            return PinryUploadResult(success: false, message: "API Token is not configured")
        }
        
        // Board ID is optional - can be empty or "0"
        let boardIDToUse = defaultBoardID.isEmpty ? "0" : defaultBoardID
        NSLog("🔥 PinryUploader: Using Board ID: '\(boardIDToUse)'")
        
        // Build URL - using v2 API like the JavaScript client
        guard let url = URL(string: "\(baseURL)/api/v2/pins/") else {
            return PinryUploadResult(success: false, message: "Invalid Pinry Base URL")
        }
        
        let request: URLRequest
        do {
            if let imageData = pin.imageData {
                // Image-based pin
                let processedImageData = try convertToJPEGIfNeeded(imageData)
                request = try createMultipartRequest(
                    url: url,
                    apiToken: apiToken,
                    imageData: processedImageData,
                    description: pin.description,
                    source: pin.source,
                    boardID: boardIDToUse
                )
            } else if let urlString = pin.url {
                // URL-based pin
                request = try createJSONRequest(
                    url: url,
                    apiToken: apiToken,
                    pinUrl: urlString,
                    description: pin.description,
                    source: pin.source,
                    boardID: boardIDToUse
                )
            } else {
                return PinryUploadResult(success: false, message: "Pin must have either image data or URL")
            }
        } catch {
            return PinryUploadResult(success: false, message: "Failed to create request: \(error.localizedDescription)")
        }
        
        // Perform upload
        NSLog("🚀 PinryUploader: Sending request to \(request.url?.absoluteString ?? "unknown")")
        NSLog("🚀 PinryUploader: HTTP Method = \(request.httpMethod ?? "unknown")")
        NSLog("🚀 PinryUploader: Headers = \(request.allHTTPHeaderFields ?? [:])")
        NSLog("🚀 PinryUploader: Body size = \(request.httpBody?.count ?? 0) bytes")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            NSLog("📡 PinryUploader: Got response!")
            
            if let httpResponse = response as? HTTPURLResponse {
                NSLog("📡 PinryUploader: Status code = \(httpResponse.statusCode)")
                NSLog("📡 PinryUploader: Response headers = \(httpResponse.allHeaderFields)")
                
                let responseBody = String(data: data, encoding: .utf8) ?? "No body"
                NSLog("📡 PinryUploader: Response body = \(responseBody)")
                
                if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                    NSLog("✅ PinryUploader: Upload successful!")
                    return PinryUploadResult(success: true, message: "Pin saved successfully!")
                } else {
                    NSLog("❌ PinryUploader: Upload failed with status \(httpResponse.statusCode)")
                    return PinryUploadResult(success: false, message: "Server error (\(httpResponse.statusCode)): \(responseBody)")
                }
            } else {
                NSLog("❌ PinryUploader: Invalid response type")
                return PinryUploadResult(success: false, message: "Invalid response from server")
            }
        } catch {
            NSLog("💥 PinryUploader: Request failed with error: \(error)")
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
    
    private func createJSONRequest(
        url: URL,
        apiToken: String,
        pinUrl: String,
        description: String,
        source: String,
        boardID: String
    ) throws -> URLRequest {
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Token \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let pinData: [String: Any] = [
            "description": description,
            "source": source,
            "board": boardID,
            "url": pinUrl
        ]
        
        NSLog("📝 PinryUploader: JSON pin data = \(pinData)")
        
        let jsonData = try JSONSerialization.data(withJSONObject: pinData)
        request.httpBody = jsonData
        
        NSLog("📝 PinryUploader: JSON body = \(String(data: jsonData, encoding: .utf8) ?? "invalid UTF8")")
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
