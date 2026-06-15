//
//  SuiJSON.swift
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

/// A Sendable, Codable enum that can represent any valid JSON value.
/// Replaces AnyCodable to ensure concurrency safety in Swift 6.
public enum SuiJSON: Codable, Sendable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: SuiJSON])
    case array([SuiJSON])
    case null

    // MARK: - Encoding
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n): try container.encode(n)
        case .bool(let b): try container.encode(b)
        case .object(let o): try container.encode(o)
        case .array(let a): try container.encode(a)
        case .null: try container.encodeNil()
        }
    }

    // MARK: - Decoding
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) { self = .string(s); return }
        if let n = try? container.decode(Double.self) { self = .number(n); return }
        if let b = try? container.decode(Bool.self) { self = .bool(b); return }
        if let a = try? container.decode([SuiJSON].self) { self = .array(a); return }
        if let o = try? container.decode([String: SuiJSON].self) { self = .object(o); return }
        if container.decodeNil() { self = .null; return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid JSON value")
    }
}

// MARK: - Expressible Conformance
extension SuiJSON: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

extension SuiJSON: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: IntegerLiteralType) { self = .number(Double(value)) }
}

extension SuiJSON: ExpressibleByFloatLiteral {
    public init(floatLiteral value: FloatLiteralType) { self = .number(value) }
}

extension SuiJSON: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension SuiJSON: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: SuiJSON...) { self = .array(elements) }
}

extension SuiJSON: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, SuiJSON)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
}

extension SuiJSON: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) { self = .null }
}

