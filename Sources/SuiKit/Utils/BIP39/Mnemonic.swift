//
//  Mnemonic.swift
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
import secp256k1
import CryptoKit

public struct Mnemonic: Equatable, Hashable, Sendable {
    public enum Error: Swift.Error {
        case invalidMnemonic
        case invalidStrengthSize
        case invalidEntropy
    }

    public let entropy: [UInt8]

    public init(strength: Int = 128) throws {
        guard strength >= 32, strength <= 256, strength % 32 == 0 else {
            throw Error.invalidStrengthSize
        }
        try self.init(entropy: SecureRandom.bytes(size: strength / 8))
    }

    public init(mnemonic: [String], wordlist: Wordlist = .english) throws {
        try self.init(entropy: Self.toEntropy(mnemonic, wordlist: wordlist))
    }

    public init(entropy: [UInt8]) throws {
        guard entropy.count > 0, entropy.count <= 32, entropy.count % 4 == 0 else {
            throw Error.invalidEntropy
        }
        self.entropy = entropy
    }

    // Generate Mnemonic Phrase
    public func mnemonic(wordlist: Wordlist = .english) -> [String] {
        return try! Self.toMnemonic(entropy, wordlist: wordlist)
    }

    // Generate BIP39 Seed
    public func seed(password: String = "", wordlist: Wordlist = .english) -> [UInt8] {
        let mnemonic = Array(self.mnemonic(wordlist: wordlist).joined(separator: " ").utf8)
        let salt = Array(("mnemonic" + password).utf8)
        return try! PBKDF2.derive(type: .sha512, password: mnemonic, salt: salt)
    }

    // Check is mnemonic phrase valid
    public static func isValid(phrase: [String], wordlist: Wordlist = .english) -> Bool {
        do {
            let _ = try Self.toEntropy(phrase, wordlist: wordlist)
            return true
        } catch {
            return false
        }
    }

    // Entropy Bytes -> Mnemonic Phrase
    public static func toMnemonic(_ entropy: [UInt8], wordlist: Wordlist = .english) throws -> [String] {
        let (checksum, csBits) = try Self.calculateChecksumBits(entropy)
        var bytes = [UInt8]()
        bytes.reserveCapacity(entropy.count + 1)
        bytes.append(contentsOf: entropy)
        bytes.append(checksum << (8 - csBits))

        var phrase = [String]()
        phrase.reserveCapacity((bytes.count * 8 + csBits) / 11)

        var hBits = (UInt16(bytes[0]) << 3), hBitsCount: UInt8 = 8
        bytes.withUnsafeBufferPointer { ptr in
            for byte in ptr.suffix(from: 1) {
                let remainderBitsCount = Int8(hBitsCount) - 3
                if remainderBitsCount >= 0 {
                    let index = hBits + (UInt16(byte) >> remainderBitsCount)
                    hBits = UInt16(byte << (8 - remainderBitsCount)) << 3
                    hBitsCount = UInt8(remainderBitsCount)
                    phrase.append(wordlist[index])
                } else {
                    hBits = hBits + (UInt16(byte) << abs(Int32(remainderBitsCount)))
                    hBitsCount += 8
                }
            }
        }

        return phrase
    }

    // Mnemonic Phrase -> Entropy Bytes
    public static func toEntropy(_ phrase: [String], wordlist: Wordlist = .english) throws -> [UInt8] {
        guard phrase.count > 0, phrase.count <= 24, phrase.count % 3 == 0 else {
            throw Error.invalidMnemonic
        }
        var hBits: UInt8 = 0, hBitsCount: UInt8 = 0
        var bytes = [UInt8]()
        bytes.reserveCapacity(Int((Float(phrase.count) * 10.99) / 8) + 1)
        for word in phrase {
            guard let index = wordlist[word] else { throw Error.invalidMnemonic }
            let remainderCount = hBitsCount + 3
            bytes.append(hBits + UInt8(index >> remainderCount))
            if remainderCount >= 8 {
                hBitsCount = remainderCount - 8
                bytes.append(UInt8(truncatingIfNeeded: index >> hBitsCount))
            } else {
                hBitsCount = remainderCount
            }
            hBits = UInt8(truncatingIfNeeded: index << (8 - hBitsCount))
        }
        if phrase.count < 24 { bytes.append(hBits) }
        let checksum = bytes.last!
        let entropy: [UInt8] = bytes.dropLast()
        let calculated = try Mnemonic.calculateChecksumBits(entropy)
        guard checksum == (calculated.checksum << (8 - calculated.bits)) else {
            throw Error.invalidMnemonic
        }
        return entropy
    }

    // Calculate checksum
    public static func calculateChecksumBits(_ entropy: [UInt8]) throws -> (checksum: UInt8, bits: Int) {
        guard entropy.count > 0, entropy.count <= 32, entropy.count % 4 == 0 else {
            throw Error.invalidEntropy
        }

        let size = entropy.count / 4 // Calculate checksum size.
        let hash = entropy.sha2(.sha256)
        return (hash[0] >> (8 - size), size)
    }
}
