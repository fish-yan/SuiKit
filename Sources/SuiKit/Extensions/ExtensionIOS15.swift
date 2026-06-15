//
//  File.swift
//  SuiKit
//
//  Created by yan on 2026-06-15.
//

import CryptoKit
import Foundation
import BigInt

extension P256.Signing.PublicKey {

    var compressedRepresentationForIOS15: Data {
        let x963 = self.x963Representation

        precondition(x963.count == 65)
        precondition(x963[0] == 0x04)

        let x = x963[1...32]
        let y = x963[33...64]

        let prefix: UInt8 = (y.last! & 1) == 0 ? 0x02 : 0x03

        return Data([prefix]) + x
    }

    init(compressedRepresentationForIOS15 data: Data) throws {
        let x963 = try P256Decompressor.x963(fromCompressed: data)
        try self.init(x963Representation: x963)
    }
}

enum P256Decompressor {

    static func x963(fromCompressed data: Data) throws -> Data {
        guard data.count == 33 else {
            throw NSError(domain: "P256", code: -1)
        }

        let prefix = data[0]
        guard prefix == 0x02 || prefix == 0x03 else {
            throw NSError(domain: "P256", code: -2)
        }

        let xData = data.dropFirst()
        let x = BigUInt(Data(xData))

        // P-256 prime:
        // FFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF
        let p = BigUInt(
            "FFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF",
            radix: 16
        )!

        let b = BigUInt(
            "5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B",
            radix: 16
        )!

        // y² = x³ - 3x + b mod p
        let x2 = (x * x) % p
        let x3 = (x2 * x) % p
        let threeX = (BigUInt(3) * x) % p
        let y2 = (x3 + p - threeX + b) % p

        // 因为 P-256 的 p % 4 == 3，所以 sqrt(y²) = y²^((p + 1) / 4) mod p
        let exponent = (p + 1) / 4
        var y = modPow(y2, exponent, p)

        let shouldBeOdd = prefix == 0x03
        let isOdd = y % 2 == 1

        if isOdd != shouldBeOdd {
            y = p - y
        }

        var result = Data([0x04])
        result.append(xData)
        result.append(y.serialize().leftPadding(to: 32))

        return result
    }

    private static func modPow(_ base: BigUInt, _ exponent: BigUInt, _ modulus: BigUInt) -> BigUInt {
        var result = BigUInt(1)
        var base = base % modulus
        var exponent = exponent

        while exponent > 0 {
            if exponent % 2 == 1 {
                result = (result * base) % modulus
            }
            exponent >>= 1
            base = (base * base) % modulus
        }

        return result
    }
}

private extension Data {
    func leftPadding(to length: Int) -> Data {
        if count >= length { return self }
        return Data(repeating: 0, count: length - count) + self
    }
}
