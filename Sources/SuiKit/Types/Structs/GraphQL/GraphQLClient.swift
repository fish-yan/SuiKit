//
//  GraphQLClient.swift
//  SuiKit
//
//  Copyright (c) 2024-2025 OpenDive
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation
import Apollo
import ApolloAPI
import SwiftyJSON

/// A wrapper struct for being able to query data from the GraphQL node.
internal struct GraphQLClient {
    private struct RequestBody: Encodable {
        let query: String
        let variables: [String: SuiJSON]
    }

    /// Given the Apollo client and a query that conforms to the GraphQLQuery type, fetch data from that endpoint and return the conformed object representing the data.
    /// - Parameters:
    ///   - client: The Apollo client used for sending the query out.
    ///   - query: The query itself containing information such as user inputs parameters, the endpoint itself, and various other metadata for making the GraphQL client functional.
    /// - Returns: A GraphQLResult object of either T.Data type, or throws an error.
    internal static func fetchQuery<T: GraphQLQuery>(client: ApolloClient, query: T) async throws -> GraphQLResult<T.Data> {
        return try await withCheckedThrowingContinuation { (con: CheckedContinuation<GraphQLResult<T.Data>, Error>) in
            _ = client.fetch(query: query) { @Sendable result in
                switch result {
                case .success(let graphQLresult):
                    con.resume(returning: graphQLresult)
                case .failure(let err):
                    con.resume(throwing: err)
                }
            }
        }
    }

    internal static func performMutation<T: GraphQLMutation>(
        client: ApolloClient,
        mutation: T
    ) async throws -> GraphQLResult<T.Data> {
        try await withCheckedThrowingContinuation { continuation in
            client.perform(mutation: mutation) { result in
                continuation.resume(with: result)
            }
        }
    }

    internal static func execute(
        endpoint: URL,
        query: String,
        variables: [String: SuiJSON] = [:]
    ) async throws -> JSON {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RequestBody(query: query, variables: variables))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw SuiError.customError(message: "GraphQL request failed")
        }

        let json = try JSON(data: data)
        if let errors = json["errors"].array, !errors.isEmpty {
            let message = errors.compactMap { $0["message"].string }.joined(separator: "; ")
            throw SuiError.customError(message: "GraphQL error: \(message)")
        }
        guard json["data"].exists(), json["data"].type != .null else {
            throw SuiError.customError(message: "Missing GraphQL data")
        }
        return json["data"]
    }
}
