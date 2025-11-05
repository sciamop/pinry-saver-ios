//
//  PinryFetcher.swift
//  PinryShared
//

import Foundation

enum PinryFetchError: Error {
    case invalidSettings
    case noAPIToken
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case httpError(Int, String)
    case decodingError(Error)
}

struct PinryFetchResult {
    let success: Bool
    let pins: [PinryPinDetail]
    let hasMore: Bool
    let totalCount: Int
    let error: String?
}

class PinryFetcher {
    
    static let shared = PinryFetcher()
    
    private init() {}
    
    // MARK: - API Configuration
    
    private var baseURL: String {
        return PinrySettings.load().pinryBaseURL
    }
    
    private var apiToken: String? {
        let settings = PinrySettings.load()
        return settings.apiToken.isEmpty ? nil : settings.apiToken
    }
    
    // MARK: - Validate Pinry Server
    
    /// Validates that the given URL is a working Pinry server by attempting to fetch pins
    func validatePinryServer(baseURL: String, apiToken: String? = nil) async -> (isValid: Bool, errorMessage: String?) {
        // Build URL with query parameters
        guard var urlComponents = URLComponents(string: "\(baseURL)/api/v2/pins/") else {
            return (false, "Invalid URL format")
        }
        
        urlComponents.queryItems = [
            URLQueryItem(name: "limit", value: "1")
        ]
        
        guard let url = urlComponents.url else {
            return (false, "Failed to construct URL")
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        
        // Add token if provided
        if let token = apiToken, !token.isEmpty {
            request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return (false, "Invalid response from server")
            }
            
            // Accept 200 OK or 401 Unauthorized (means Pinry is there, just needs auth for private pins)
            if httpResponse.statusCode == 200 || httpResponse.statusCode == 401 {
                // Try to decode to verify it's actually Pinry
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                
                if let _ = try? decoder.decode(PinryPinsResponse.self, from: data) {
                    return (true, nil)
                }
                
                // Even if decode fails, 200/401 from /api/v2/pins/ is good enough
                return (true, nil)
            } else if httpResponse.statusCode == 404 {
                return (false, "This doesn't appear to be a Pinry server (API not found)")
            } else {
                return (false, "Server returned error code \(httpResponse.statusCode)")
            }
            
        } catch {
            return (false, "Unable to connect: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Fetch Pins Method
    
    func fetchPins(offset: Int = 0, limit: Int = 20) async -> PinryFetchResult {
        // Validate settings
        guard !baseURL.isEmpty else {
            return PinryFetchResult(
                success: false,
                pins: [],
                hasMore: false,
                totalCount: 0,
                error: "Pinry Base URL is not configured"
            )
        }
        
        // API token is now optional - reading public pins doesn't require it
        let token = apiToken
        
        // Build URL with query parameters
        guard var urlComponents = URLComponents(string: "\(baseURL)/api/v2/pins/") else {
            return PinryFetchResult(
                success: false,
                pins: [],
                hasMore: false,
                totalCount: 0,
                error: "Invalid Pinry Base URL"
            )
        }
        
        urlComponents.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "ordering", value: "-id")  // Newest first
        ]
        
        guard let url = urlComponents.url else {
            return PinryFetchResult(
                success: false,
                pins: [],
                hasMore: false,
                totalCount: 0,
                error: "Failed to construct URL"
            )
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // Add token if available
        if let token = token, !token.isEmpty {
            request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        }
        
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // Perform request
        var responseData: Data?
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            responseData = data
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return PinryFetchResult(
                    success: false,
                    pins: [],
                    hasMore: false,
                    totalCount: 0,
                    error: "Invalid response from server"
                )
            }
            
            guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                return PinryFetchResult(
                    success: false,
                    pins: [],
                    hasMore: false,
                    totalCount: 0,
                    error: "Server error (\(httpResponse.statusCode)): \(errorMessage)"
                )
            }
            
            // Decode response
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            
            let pinsResponse = try decoder.decode(PinryPinsResponse.self, from: data)
            
            return PinryFetchResult(
                success: true,
                pins: pinsResponse.results,
                hasMore: pinsResponse.next != nil,
                totalCount: pinsResponse.count,
                error: nil
            )
            
        } catch let error as DecodingError {
            // Debug: print actual JSON response
            if let data = responseData,
               let jsonString = String(data: data, encoding: .utf8) {
                print("❌ Decoding Error - Raw JSON Response:")
                print(jsonString.prefix(1000)) // First 1000 chars
                print("\n❌ Decoding Error Details:")
                print(error)
            }
            
            return PinryFetchResult(
                success: false,
                pins: [],
                hasMore: false,
                totalCount: 0,
                error: "Failed to decode response: \(error.localizedDescription)"
            )
        } catch {
            return PinryFetchResult(
                success: false,
                pins: [],
                hasMore: false,
                totalCount: 0,
                error: "Network error: \(error.localizedDescription)"
            )
        }
    }
}

