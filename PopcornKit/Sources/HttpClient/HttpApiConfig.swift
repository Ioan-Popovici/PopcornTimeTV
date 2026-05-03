//
//  HttpApiConfig.swift
//  
//
//  Created by Alexandru Tudose on 15.12.2021.
//

import Foundation


struct HttpApiConfig {
    var serverURL: String
    
    var configuration: URLSessionConfiguration = {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForResource = 30
//        configuration.urlCache = nil
//        configuration.requestCachePolicy = .returnCacheDataDontLoad
        configuration.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_16_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/80.0.3987.138 Safari/"]
        return configuration
    }()
    
    var validStatuses = (200...299)
    var missingSession = [401]
    var closeSession: @Sendable (_ error: Error) -> Void = { error in  }
    var apiErrorDecoder: @Sendable (_ data: Data) -> Error? = { data in return nil } // used de extract errors from data
}

// User-Agent Header; see https://tools.ietf.org/html/rfc7231#section-5.5.3
// Example: `iOS Example/1.0 (org.alamofire.iOS-Example; build:1; iOS 10.0.0) Alamofire/4.0.0`
let userAgent: String = {
    if let info = Bundle.main.infoDictionary {
        let executable = info[kCFBundleExecutableKey as String] as? String ?? "Unknown"
        let bundle = info[kCFBundleIdentifierKey as String] as? String ?? "Unknown"
        let appVersion = info["CFBundleShortVersionString"] as? String ?? "Unknown"
        let appBuild = info[kCFBundleVersionKey as String] as? String ?? "Unknown"

        let osNameVersion: String = {
            let version = ProcessInfo.processInfo.operatingSystemVersion
            let versionString = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"

            let osName: String = {
                #if os(iOS)
                    return "iOS"
                #elseif os(watchOS)
                    return "watchOS"
                #elseif os(tvOS)
                    return "tvOS"
                #elseif os(macOS)
                    return "OS X"
                #elseif os(Linux)
                    return "Linux"
                #else
                    return "Unknown"
                #endif
            }()

            return "\(osName) \(versionString)"
        }()

        return "\(executable)/\(appVersion) (\(bundle); build:\(appBuild); \(osNameVersion))"
    }

    return "PopcornTime SwiftUI"
}()
