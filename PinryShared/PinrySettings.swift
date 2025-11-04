//
//  PinrySettings.swift
//  PinryShared
//

import Foundation

struct PinrySettings: Codable {
    var pinryBaseURL: String
    var defaultBoardID: String
    var apiToken: String  // Store as plaintext for now
    
    static let shared = PinrySettings()
    
    private init() {
        self.pinryBaseURL = ""
        self.defaultBoardID = ""
        self.apiToken = ""
    }
    
    // MARK: - UserDefaults Storage
    
    private static let suiteName = "group.com.example.pinry"
    private static let baseURLKey = "pinryBaseURL"
    private static let defaultBoardIDKey = "defaultBoardID"
    private static let apiTokenKey = "api_token"
    
    // Cache to avoid repeated UserDefaults access
    private static var cachedSettings: PinrySettings?
    private static var lastLoadTime: Date?
    private static let cacheTimeout: TimeInterval = 5.0
    
    static func load() -> PinrySettings {
        // Return cached settings if recent
        if let cached = cachedSettings,
           let lastLoad = lastLoadTime,
           Date().timeIntervalSince(lastLoad) < cacheTimeout {
            return cached
        }
        
        // Try to load from App Group UserDefaults
        if let defaults = UserDefaults(suiteName: suiteName) {
            var settings = PinrySettings.shared
            settings.pinryBaseURL = defaults.string(forKey: baseURLKey) ?? ""
            settings.defaultBoardID = defaults.string(forKey: defaultBoardIDKey) ?? ""
            settings.apiToken = defaults.string(forKey: apiTokenKey) ?? ""
            
            // Cache the loaded settings
            cachedSettings = settings
            lastLoadTime = Date()
            
            return settings
        }
        
        // Fallback to cached or default
        return cachedSettings ?? PinrySettings.shared
    }
    
    static func save(_ settings: PinrySettings?) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        
        let settingsToSave = settings ?? PinrySettings.shared
        
        defaults.set(settingsToSave.pinryBaseURL, forKey: baseURLKey)
        defaults.set(settingsToSave.defaultBoardID, forKey: defaultBoardIDKey)
        defaults.set(settingsToSave.apiToken, forKey: apiTokenKey)
        
        // Update cache
        cachedSettings = settingsToSave
        lastLoadTime = Date()
        
        // Don't use synchronize() - it's deprecated and can block
        // UserDefaults automatically persists changes
    }
    
    // Force refresh cache (call after saving in main app)
    static func invalidateCache() {
        cachedSettings = nil
        lastLoadTime = nil
    }
}
