//
//  MainnetGraphQLIntegrationTests.swift
//  SuiKitTests
//

import BigInt
import Foundation
import XCTest
@testable import SuiKit

/// Read-only tests for fields that have changed during the JSON-RPC migration.
///
/// They are opt-in because they query mainnet. Run with
/// `SUIKIT_MAINNET_INTEGRATION=1 swift test --filter MainnetGraphQLIntegrationTests`.
final class MainnetGraphQLIntegrationTests: XCTestCase {
    private let address = "0x6a5dc653607568255f88da23004ae590c357533b95f07d9f8bf29f7066026736"

    func testAddressBalanceDoesNotRequireCoinObjects() async throws {
        try requireMainnetIntegration()
        let provider = GraphQLSuiProvider(connection: MainnetConnection())

        let balance = try await provider.getBalance(owner: address, coinType: "0x2::sui::SUI")
        XCTAssertNotNil(balance.addressBalance)
        XCTAssertNotNil(balance.coinBalance)

        let total = try XCTUnwrap(BigInt(balance.totalBalance))
        let addressBalance = try XCTUnwrap(BigInt(balance.addressBalance ?? ""))
        let coinBalance = try XCTUnwrap(BigInt(balance.coinBalance ?? ""))
        XCTAssertEqual(total, addressBalance + coinBalance)

        let coins = try await provider.getCoins(owner: address, coinType: "0x2::sui::SUI")
        XCTAssertTrue(coins.data.isEmpty)
        XCTAssertGreaterThan(addressBalance, 0)
    }

    func testSystemObjectUsesCurrentMoveObjectSelection() async throws {
        try requireMainnetIntegration()
        let provider = GraphQLSuiProvider(connection: MainnetConnection())

        let response = try await provider.getObject(
            objectId: "0x5",
            options: SuiObjectDataOptions(showContent: true)
        )

        let object = try XCTUnwrap(response?.data)
        XCTAssertEqual(object.objectId, try Inputs.normalizeSuiAddress(value: "0x5"))
        XCTAssertNotNil(object.content)
    }

    func testAddressBalanceTransferSimulatesFromTypedTransaction() async throws {
        try requireMainnetIntegration()
        let provider = GraphQLSuiProvider(connection: MainnetConnection())
        let transaction = try TransactionBlock()
        _ = try transaction.transferMaxFromAddressBalance(toAddress: address)
        try transaction.setSender(sender: address)

        // Build resolves the address-balance withdrawal and gas budget without
        // submitting anything. The second call exercises the public typed
        // simulation API rather than decoding BCS at the provider boundary.
        _ = try await transaction.build(provider)
        let result = try await provider.simulateTransaction(
            transaction: try transaction.blockData.buildTransactionData(),
            checksEnabled: true,
            doGasSelection: true
        )

        XCTAssertNotEqual(result.effects?.status.status, .failure)
    }

    func testProtocolConfigsUsesPluralCurrentSchemaField() async throws {
        try requireMainnetIntegration()
        let provider = GraphQLSuiProvider(connection: MainnetConnection())

        let config = try await provider.getProtocolConfig(version: nil)
        XCTAssertFalse(config.protocolVersion.isEmpty)
        XCTAssertFalse(config.attributes.isEmpty)
    }

    private func requireMainnetIntegration() throws {
        guard ProcessInfo.processInfo.environment["SUIKIT_MAINNET_INTEGRATION"] == "1" else {
            throw XCTSkip("Set SUIKIT_MAINNET_INTEGRATION=1 to run read-only mainnet tests")
        }
    }
}
