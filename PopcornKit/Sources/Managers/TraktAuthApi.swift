//
//  TraktAuthApi.swift
//  
//
//  Created by Alexandru Tudose on 20.12.2021.
//

import Foundation


public class TraktAuthApi: @unchecked Sendable {
    nonisolated(unsafe) public static var shared = TraktAuthApi()
    
    /// OAuth state parameter added for extra security against cross site forgery.
    fileprivate var state: String?
    
    let client = HttpClient(config: .init(serverURL: Trakt.base, configuration: {
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = Trakt.Headers.Default
        return configuration
    }()))
    
    
    /// ============================= Apple TV =============================
    /**
     Generate code to authenticate device on web.
     
     - Parameter completion: The completion handler for the request containing the code for the user to enter to the validation url (`https://trakt.tv/activate/authorize`), the code for the device to get the access token, the expiery date of the displat code and the time interval that the program is to check whether the user has authenticated and an optional error if request fails.
     */
    public func generateCode() async throws -> TraktUserAuthorizeCode {
        let path = Trakt.auth + Trakt.device + Trakt.code
        return try await client.request(.post, path: path, parameters: ["client_id": Trakt.apiKey]).responseDecode()
    }
    
    public func check(deviceCode: String) async throws {
        let path = Trakt.auth + Trakt.device + Trakt.token
        
        let params = ["grant_type": OAuthGrantType.Code.rawValue,
                      "code": deviceCode,
                      "client_id": Trakt.apiKey,
                      "client_secret": Trakt.apiSecret]
        
        let credentials: TraktOauthResponse = try await client.request(.post, path: path, parameters: params).responseDecode()
        TraktSession.shared.storeCredentials(credentials.oauthCredential)
    }
    /// ============================= Apple TV =============================
    
    /// ============================= ipad =============================
    /// 1 step of the authentication process, open this url in browser
    public func authorizationUrl(appScheme: String) -> URL {
        state = .random(of: 15)
        
        return URL(string: Trakt.base + Trakt.auth + "/authorize?client_id=" + Trakt.apiKey + "&redirect_uri=\(appScheme)%3A%2F%2Ftrakt&response_type=code&state=\(state!)")!
    }
    
    /**
      2 step of the authentication process
     
     - Parameter url: The redirect URI recieved from step 1.
     */
    public func authenticate(_ url: URL) async throws {
        defer { state = nil }
        
        guard let query = url.query?.queryString, let code = query["code"], query["state"] == state else {
            throw NSError(domain: "com.popcorntimetv.popcornkit.error", code: -1, userInfo: [NSLocalizedDescriptionKey: "An unknown error occured."])
        }
        

        let params = ["grant_type": OAuthGrantType.Code.rawValue,
                      "code": code,
                      "redirect_uri": "PopcornTime://trakt",
                      "client_id": Trakt.apiKey,
                      "client_secret": Trakt.apiSecret]
        
        let credentials: TraktOauthResponse = try await client.request(.post, path: Trakt.auth + Trakt.token, parameters: params).responseDecode()
        TraktSession.shared.storeCredentials(credentials.oauthCredential)
    }
    /// ============================= ipad =============================
    
    func refreshToken(refreshToken: String) async throws -> OAuthCredential {
        let params = ["grant_type": OAuthGrantType.Refresh.rawValue,
                      "refresh_token": refreshToken,
                      "client_id": Trakt.apiKey,
                      "client_secret": Trakt.apiSecret]
        do {
            let credentials: TraktOauthResponse = try await client.request(.post, path: Trakt.auth + Trakt.token, parameters: params).responseDecode()
            TraktSession.shared.storeCredentials(credentials.oauthCredential)
            return credentials.oauthCredential
        } catch let error as APIError {
            switch error.type {
            case .unacceptableStatusCode(code: 400): // refresh token not good
                TraktSession.shared.logout()
            default:
                break
            }
            throw error
        }
    }
}

public struct TraktUserAuthorizeCode: Decodable {
    public var userCode: String
    public var deviceCode: String
    var expiresIn: Int
    public var interval: Int
    
    public var expiresInDate: Date {
        return Date().addingTimeInterval(Double(expiresIn))
    }
}

private enum OAuthGrantType: String {
    case Code = "authorization_code"
    case ClientCredentials = "client_credentials"
    case PasswordCredentials = "password"
    case Refresh = "refresh_token"
}

private struct TraktOauthResponse: Decodable {
    var accessToken: String
    var tokenType: String
    var expiresIn: Int?
    var refreshToken: String?
    
    /// Boolean value indicating the expired status of the credential.
    var expired: Bool {
        return self.expiration?.compare(Date()) == .orderedAscending
    }
    var expiration: Date? {
        // Expiration is optional, but recommended in the OAuth2 spec. It not provide, assume distantFuture == never expires.
        var expireDate = Date.distantFuture
        if let expiresIn = expiresIn {
            expireDate = Date(timeIntervalSinceNow: Double(expiresIn))
        }
        return expireDate
    }
    
    var oauthCredential: OAuthCredential {
        return OAuthCredential(accessToken: accessToken, tokenType: tokenType, refreshToken: refreshToken, expiration: expiration)
    }
}
