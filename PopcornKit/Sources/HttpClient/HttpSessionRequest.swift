//
//  File.swift
//  
//
//  Created by Alexandru Tudose on 15.12.2021.
//

import Foundation
import ObjectMapper


struct HttpSessionRequest: Sendable {
    var request: URLRequest
    var session: URLSession = .shared
    var validStatuses = (200...299)
    var missingSession = [401]
    var closeSession: @Sendable (_ error: Error) -> Void = { error in  }
    var apiErrorDecoder: @Sendable (_ data: Data) -> Error? = { data in return nil } // used de extract errors from data
    
    func response() async throws {
        let (data, response): (Data, URLResponse) = try await session.data(for: request)
        try validate(request: request, response: response, data: data)
    }
    
    func responseData() async throws -> Data {
        let (data, response): (Data, URLResponse) = try await session.data(for: request)
        try validate(request: request, response: response, data: data)
        return data
    }
    
    func responseDecode<T: Decodable>(keyPath: String? = nil, decoder: JSONDecoder = .default) async throws -> T {
        let (data, response): (Data, URLResponse) = try await session.data(for: request)
        try validate(request: request, response: response, data: data)
        
        do {
            var object: T
            if let keyPath = keyPath {
                object = try decoder.decode(T.self, from: data, keyPath: keyPath, separator: ".")
            } else {
                object = try decoder.decode(T.self, from: data)
            }
            return object
        } catch (let error as DecodingError) {
            print(error.debugDescription)
            throw error
        } catch {
            print("unknown error", error.localizedDescription)
            throw error
        }
    }
    
    func responseMapable<T: Mappable>(keyPath: String? = nil, context: MapContext? = nil) async throws -> [T] {
        let (data, response): (Data, URLResponse) = try await session.data(for: request)
        try validate(request: request, response: response, data: data)
        
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw APIError(type: .missingContent)
        }
        guard let response = Mapper<T>(context: context).mapArray(JSONString: jsonString) else {
            throw APIError(type:.couldNotDecodeResponse)
        }
        
        return response
    }
    
    func responseMapable<T: Mappable>(keyPath: String? = nil, context: MapContext? = nil) async throws -> T {
        let (data, response): (Data, URLResponse) = try await session.data(for: request)
        try validate(request: request, response: response, data: data)
        
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw APIError(type: .missingContent)
        }
        guard let response = Mapper<T>(context: context).map(JSONString: jsonString) else {
            throw APIError(type:.couldNotDecodeResponse)
        }
        
        return response
    }
    
    func validate(request: URLRequest, response: URLResponse, data: Data?) throws {
        guard let statusCode = (response as? HTTPURLResponse)?.statusCode else {
            throw APIError(type: .invalidHttpStatusCode)
        }
        
        var apiError: Error?
        if let data = data {
            apiError = apiErrorDecoder(data)
        }
        
        guard validStatuses.contains(statusCode) else {
            
            print("\n Request failed: ",
                  request.httpMethod ?? "",
                  request.url?.absoluteString ?? "",
                  "\n\tResponse: " + (data.flatMap({ String(data:$0, encoding: .utf8) }) ?? ""))
            
            let accessDenied = missingSession.contains(statusCode)
            
            if accessDenied {
                let closeSession = self.closeSession
                DispatchQueue.main.async {
                    closeSession(APIError(type: .missingSession))
                }
            }
            
            throw apiError ?? APIError(type: .unacceptableStatusCode(code: statusCode))
        }
        
        if let apiError = apiError {
            throw apiError
        }
    }
}

