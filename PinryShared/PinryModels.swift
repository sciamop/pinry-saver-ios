//
//  PinryModels.swift
//  PinryShared
//

import Foundation

// MARK: - Pin Response Models

struct PinryPinsResponse: Codable {
    let count: Int
    let next: String?
    let previous: String?
    let results: [PinryPinDetail]
}

struct PinryPinDetail: Codable, Identifiable {
    let id: Int
    let url: String?
    let description: String?
    let image: PinryImage
    let submitter: PinrySubmitter?
    let tags: [String]?
    
    enum CodingKeys: String, CodingKey {
        case id
        case url
        case description
        case image
        case submitter
        case tags
    }
}

struct PinryImage: Codable {
    let id: Int?
    let image: String?
    let width: Int?
    let height: Int?
    let thumbnail: PinryImageSize?
    let square: PinryImageSize?
    let standard: PinryImageSize?
    
    enum CodingKeys: String, CodingKey {
        case id
        case image
        case width
        case height
        case thumbnail
        case square
        case standard
    }
    
    // Helper to get the best available thumbnail URL
    var bestImageUrl: String? {
        return thumbnail?.url ?? square?.url ?? standard?.url
    }
    
    // Full-size original image URL
    var fullSizeUrl: String? {
        return image
    }
}

struct PinryImageSize: Codable {
    let image: String
    let width: Int?
    let height: Int?
    
    // Convenience property to match our usage
    var url: String {
        return image
    }
}

struct PinrySubmitter: Codable {
    let username: String
    let email: String?
    let token: String?
    let gravatar: String?
    let resourceLink: String?
    
    enum CodingKeys: String, CodingKey {
        case username
        case email
        case token
        case gravatar
        case resourceLink = "resource_link"
    }
}

