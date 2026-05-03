//
//  JSONCache.swift
//  PROJECT_NAME
//
//  Created by PROJECT_AUTHOR on PROJECT_CREATION_DATE.
//

import Foundation

/// Usage Ex:
/// - loading -- `lazy var creditCards: [CreditCard]? = JSONCache.creditCards.loadFromFile()`
/// - saving -- `JSONCache.creditCards.saveToFile(cards)`
enum JSONCache {
    
    nonisolated(unsafe) private static var operationsQueues = [String : DispatchQueue]()
    
//    static var bookingHistory: CodableCaching<[Booking]> {
//        return userResource()
//    }
//
//    static var community: CodableCaching<[Post]> {
//        return resource()
//    }
    
//    static var currentUser: CodableCaching<User> {
//        return userResource()
//    }
    
    static func clearAllSavedResource() {
        CodableCaching<Any>.deleteCachingDirectory()
    }
}

extension JSONCache {
    fileprivate static func userResourceID(function: String = #function) -> String {
        let id = "" // Session.currentUserID ?? ""
        return function + "_" + id
    }
    
    fileprivate static func userResource<T>(function: String = #function) -> CodableCaching<T> {
        let resourceID = userResourceID(function: function)
        return CodableCaching(resourceID: resourceID, queue: createDispatchQueue(forID: resourceID))
    }
    
    fileprivate static func resource<T>(function: String = #function) -> CodableCaching<T> {
        let resourceID = function
        return CodableCaching(resourceID: resourceID, queue: createDispatchQueue(forID: resourceID))
    }
    
    fileprivate static func createDispatchQueue(forID id: String) -> DispatchQueue {
        if let queue = operationsQueues[id] {
            return queue
        }

        let queue = DispatchQueue(label: id, attributes: .concurrent)
        operationsQueues[id] = queue

        return queue
    }
}

