//
//  UserDefault.swift
//  PROJECT_NAME
//
//  Created by PROJECT_AUTHOR on PROJECT_CREATION_DATE.
//

import Foundation

// explanation https://dev.to/kodelit/userdefaults-property-wrapper-issues-solutions-4lk9#improved-user-default
// repo https://github.com/kodelit/UserDefaultPropertyWrapper
@propertyWrapper
struct UserDefault<T>: @unchecked Sendable {
  let key: String
  let defaultValue: T
  
  var wrappedValue: T {
    get {
        let value = UserDefaults.standard.object(forKey: key) as? T
        switch value as Any {
            //swiftlint:disable:next syntactic_sugar
        case Optional<Any>.some(let containedValue):
            //swiftlint:disable:next force_cast
            return containedValue as! T
        case Optional<Any>.none:
            return defaultValue
        default:
            // type `T` is not optional
            return value ?? defaultValue
      }
    }
    set {
        switch newValue as Any {
            //swiftlint:disable:next syntactic_sugar
        case Optional<Any>.some(let containedValue):
            UserDefaults.standard.set(containedValue, forKey: key)
        case Optional<Any>.none:
            UserDefaults.standard.removeObject(forKey: key)
        default:
            // type `T` is not optional
            UserDefaults.standard.set(newValue, forKey: key)
      }
    }
  }
}
