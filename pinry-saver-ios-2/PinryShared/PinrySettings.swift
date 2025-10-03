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
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return PinrySettings.shared
        }
        
        var settings = PinrySettings.shared
        settings.pinryBaseURL = defaults.string(forKey: baseURLKey) ?? ""
        settings.defaultBoardID = defaults.string(forKey: defaultBoardIDKey) ?? ""
        settings.apiToken = defaults.string(forKey: apiTokenKey) ?? ""
        
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
