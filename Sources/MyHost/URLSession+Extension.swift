//
//  URLSession+Extension.swift
//  Poster
//
//  Created by zhaoxin on 2021/12/14.
//  Copyright © 2021 ParusSoft.com. All rights reserved.
//

import Foundation

@available(watchOS, deprecated: 8.0, message: "Use the built-in API instead")
@available(iOS, deprecated: 15.0, message: "Use the built-in API instead")
@available(macOS, deprecated: 12.0, message: "Use the built-in API instead")
extension URLSession {
    func data(from url: URL) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = self.dataTask(with: url) { data, response, error in
                guard let data = data, let response = response else {
                    let error = error ?? URLError(.badServerResponse)
                    return continuation.resume(throwing: error)
                }

                continuation.resume(returning: (data, response))
            }

            task.resume()
        }
    }
//    
////    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
////        try await withCheckedThrowingContinuation { continuation in
////            let task = self.dataTask(with: request) { data, response, error in
////                guard let data = data, let response = response else {
////                    let error = error ?? URLError(.badServerResponse)
////                    return continuation.resume(throwing: error)
////                }
////                
////                continuation.resume(returning: (data, response))
////            }
////            
////            task.resume()
////        }
////    }
}
