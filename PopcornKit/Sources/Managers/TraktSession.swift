

import Foundation

public class TraktSession: @unchecked Sendable {
    nonisolated(unsafe) public static var shared = TraktSession()
    var refreshTask: Task<OAuthCredential, Error>?
    
    private var credentials: OAuthCredential? = {
        if let data = Session.traktCredentials,
           let credentials = try? JSONDecoder().decode(OAuthCredential.self, from: data) {
                return credentials
        }
        return nil
    }()
    
    public func logout() {
        credentials = nil
        Session.traktCredentials = nil
    }
    
    public func isLoggedIn() -> Bool {
        return credentials != nil
    }
    
    func traktCredentials() async throws -> OAuthCredential {
        /// there might be a refresh token request onflight, we should wait for it
        if let task = refreshTask {
            return try await task.value
        }
        
        if let credentials = credentials {
            if credentials.expired, let refreshToken = credentials.refreshToken {
                self.refreshTask = Task {
                    return try await TraktAuthApi.shared.refreshToken(refreshToken: refreshToken)
                }
                let credentials = try await refreshTask!.value
                storeCredentials(credentials)
                self.refreshTask = nil
                return credentials
            } else {
                return credentials
            }
        }
        
        throw APIError(type: .missingSession)
    }
    
    func storeCredentials(_ credentials: OAuthCredential) {
        self.credentials = credentials
        if let data = try? JSONEncoder().encode(credentials) {
            Session.traktCredentials = data
        }
    }
}

/**
 `OAuthCredential` models the credentials returned from an OAuth server, storing the token type, access & refresh tokens, and whether the token is expired.
 
 OAuth credentials can be stored in the user's keychain, and retrieved on subsequent launches.
 */
struct OAuthCredential: Codable {

    /// The OAuth access token.
    var accessToken: String
    
    /// The OAuth token type (e.g. "bearer").
    var tokenType: String
    
    /// The OAuth refresh token.
    var refreshToken: String?
    
    /// Boolean value indicating the expired status of the credential.
    var expired: Bool {
        return self.expiration?.compare(Date()) == .orderedAscending
    }
    
    /// The expiration date of the credential.
    var expiration: Date?
    
    var description: String {
        return "<\(type(of: self)): \(String(format: "%p", unsafeBitCast(self, to: Int.self))); accessToken = '\(self.accessToken)'; tokenType = '\(self.tokenType)'; refreshToken = '\(self.refreshToken ?? "none")'; expiration = \(self.expiration ?? Date.distantFuture)>"
    }
}
