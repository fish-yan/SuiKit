//
//  FundsWithdrawal.swift
//  SuiKit
//

import Foundation

/// The address-balance source reserved by a funds-withdrawal transaction input.
public enum FundsWithdrawalSource: UInt8, Sendable {
    /// Withdraw from the transaction sender's address balance.
    case sender

    /// Withdraw from the gas sponsor's address balance.
    case sponsor
}

/// A reservation to withdraw a typed balance from Sui's funds accumulator.
///
/// The runtime converts this input to `sui::funds_accumulator::Withdrawal`, which
/// can be passed to `0x2::coin::redeem_funds` to obtain a transferable `Coin<T>`.
public struct FundsWithdrawal: KeyProtocol {
    /// Amount to reserve, in the coin type's smallest unit.
    public let amount: UInt64

    /// The Move coin type to withdraw.
    public let coinType: TypeTag

    /// The address balance from which to reserve the funds.
    public let source: FundsWithdrawalSource

    public init(amount: UInt64, coinType: TypeTag, source: FundsWithdrawalSource = .sender) {
        self.amount = amount
        self.coinType = coinType
        self.source = source
    }

    public func serialize(_ serializer: Serializer) throws {
        // Reservation::MaxAmountU64
        try serializer.uleb128(UInt(0))
        try Serializer.u64(serializer, amount)

        // WithdrawalType::Balance
        try serializer.uleb128(UInt(0))
        try Serializer._struct(serializer, value: coinType)

        try serializer.uleb128(UInt(source.rawValue))
    }

    public static func deserialize(from deserializer: Deserializer) throws -> FundsWithdrawal {
        guard try deserializer.uleb128() == 0 else {
            throw SuiError.customError(message: "Unsupported funds withdrawal reservation")
        }
        let amount = try Deserializer.u64(deserializer)

        guard try deserializer.uleb128() == 0 else {
            throw SuiError.customError(message: "Unsupported funds withdrawal type")
        }
        let coinType: TypeTag = try Deserializer._struct(deserializer)

        guard let source = FundsWithdrawalSource(rawValue: UInt8(try deserializer.uleb128())) else {
            throw SuiError.customError(message: "Unsupported funds withdrawal source")
        }
        return FundsWithdrawal(amount: amount, coinType: coinType, source: source)
    }
}
