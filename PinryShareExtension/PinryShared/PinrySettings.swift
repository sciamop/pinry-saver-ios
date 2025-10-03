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
    
    static func load() -> PinrySettings {
        NSLog("🔍 PinrySettings: Attempting to load from App Group '\(suiteName)'")
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            NSLog("❌ PinrySettings: Failed to access App Group UserDefaults!")
            return PinrySettings.shared
        }
        
        NSLog("✅ PinrySettings: Successfully accessed App Group UserDefaults")
        
        var settings = PinrySettings.shared
        let loadedBaseURL = defaults.string(forKey: baseURLKey) ?? ""
        let loadedBoardID = defaults.string(forKey: defaultBoardIDKey) ?? ""
        let loadedToken = defaults.string(forKey: apiTokenKey) ?? ""
        
        settings.pinryBaseURL = loadedBaseURL
        settings.defaultBoardID = loadedBoardID
        settings.apiToken = loadedToken
        
        NSLog("🔍 PinrySettings: Loaded settings from App Group:")
        NSLog("  📍 Base URL: '\(loadedBaseURL)'")
        NSLog("  📋 Board ID: '\(loadedBoardID)'")
        NSLog("  🔐 API Token: '\(loadedToken)' (\(loadedToken.count) chars)")
        
        return settings
    }
    
    static func save(_ settings: PinrySettings?) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        
        let settingsToSave = settings ?? PinrySettings.shared
        
        defaults.set(settingsToSave.pinryBaseURL, forKey: baseURLKey)
        defaults.set(settingsToSave.defaultBoardID, forKey: defaultBoardIDKey)
        defaults.set(settingsToSave.apiToken, forKey: apiTokenKey)
        defaults.synchronize()
    }
}
