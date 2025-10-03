//
//  KeychainStore.swift
//  PinryShared
//

import Foundation
import Security

class KeychainStore {
    
    // MARK: - Keychain Configuration
    
    private static let service = "com.example.pinry"
    // Try different access group formats to ensure compatibility
    private static let accessGroup = "com.example.pinryshared" // Simplified without AppIdentifierPrefix
    private static let account = "api_token"
    
    // MARK: - API Token Storage
    
    static func storeAPIToken(_ token: String) -> Bool {
        NSLog("KeychainStore: storeAPIToken called with token length: \(token.count)")
        
        guard let data = token.data(using: .utf8) else { 
            print("KeychainStore: Failed to convert token to data")
            NSLog("KeychainStore: Failed to convert token to data")
            return false 
        }
        
        NSLog("KeychainStore: Token converted to data, length: \(data.count)")
        
        // Delete existing item if it exists
        NSLog("KeychainStore: Attempting to delete existing token")
        let deleteResult = deleteAPIToken()
        NSLog("KeychainStore: Delete result: \(deleteResult)")
        
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrSynchronizable as String: false  // Try without sync first
        ]
        
        NSLog("KeychainStore: Attempting to add item without access group")
        // Try without access group first (for simulator/development)
        var status = SecItemAdd(query as CFDictionary, nil)
        NSLog("KeychainStore: SecItemAdd status without access group: \(status)")
        
        if status != errSecSuccess {
            NSLog("KeychainStore: Adding without access group failed with status: \(status)")
            
            // Try with access group
            query[kSecAttrAccessGroup as String] = accessGroup
            NSLog("KeychainStore: Attempting to add with access group: \(accessGroup)")
            status = SecItemAdd(query as CFDictionary, nil)
            NSLog("KeychainStore: SecItemAdd status with access group: \(status)")
            
            if status != errSecSuccess {
                NSLog("KeychainStore: Adding with access group failed with status: \(status)")
                return false
            }
        }
        
        NSLog("KeychainStore: Successfully stored API token!")
        print("KeychainStore: Successfully stored API token!")
        return true
    }
    
    static func retrieveAPIToken() -> String? {
        // Try without access group first
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecAttrSynchronizable as String: false
        ]
        
        var result: AnyObject?
        var status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status != errSecSuccess {
            // Try with access group
            query[kSecAttrAccessGroup as String] = accessGroup
            query[kSecAttrSynchronizable as String] = true
            status = SecItemCopyMatching(query as CFDictionary, &result)
        }
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            print("KeychainStore: Failed to retrieve API token with status: \(status)")
            return nil
        }
        
        return token
    }
    
    static func deleteAPIToken() -> Bool {
        // Try without access group first
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
        
        var status = SecItemDelete(query as CFDictionary)
        
        if status != errSecSuccess && status != errSecItemNotFound {
            // Try with access group
            query[kSecAttrAccessGroup as String] = accessGroup
            query[kSecAttrSynchronizable as String] = true
            status = SecItemDelete(query as CFDictionary)
        }
        
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    static func hasAPIToken() -> Bool {
        return retrieveAPIToken() != nil
    }
}
