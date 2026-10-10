import BigInt
import Foundation
import SwiftyJSON
import XCTest
@testable import SuiKit

final class SuiTransferBuilderTests: XCTestCase {
    private let sui = "0x2::sui::SUI"
    private let token = "0x3::test::TOKEN"
    private let budget: BigInt = 5_000_000

    private func funds(_ address: BigInt, _ balances: [UInt64], type: String = "0x2::sui::SUI") throws -> SuiTransferBuilder.Funds {
        let coins = try balances.enumerated().map { index, value in
            try CoinStruct(coinType: type, coinObjectId: "0x\(String(index + (type == sui ? 10 : 20), radix: 16))",
                version: "1", digest: "11111111111111111111111111111111",
                balance: String(value), previousTransaction: "11111111111111111111111111111111")
        }
        return try .init(address: address, coins: coins)
    }

    func testFifteenSuiUsesCoinsWhenAddressBalanceIsInsufficient() throws {
        let funds = try funds(9_619_702_204, [3_000_000_000, 4_000_000_000])
        let plan = try SuiTransferBuilder.plan(amount: 15_000_000_000, native: true, budget: budget, gas: funds, token: funds)
        XCTAssertEqual(plan.coins.count, 2)
        XCTAssertTrue(plan.payments.isEmpty)
        XCTAssertEqual(plan.withdrawal, 8_000_000_000)
        XCTAssertLessThanOrEqual(BigInt(plan.withdrawal) + budget, funds.address)
        let json = try encode(plan)
        let commands = json["kind"]["programmableTransaction"]["commands"].arrayValue
        XCTAssertTrue(commands.contains { $0["mergeCoins"].exists() })
        XCTAssertTrue(commands.contains { $0["splitCoins"].exists() })
        XCTAssertEqual(commands.filter { $0["transferObjects"].exists() }.count, 2)
    }

    func testCoinOnlyTransferUsesMultipleGasObjectsWithoutOwnedInputDuplicates() throws {
        let funds = try funds(0, [7_000_000_000, 9_000_000_000])
        let plan = try SuiTransferBuilder.plan(amount: 15_000_000_000, native: true, budget: budget, gas: funds, token: funds)
        XCTAssertEqual(plan.payments.count, 2)
        XCTAssertTrue(plan.coins.isEmpty)
        XCTAssertEqual(plan.withdrawal, 0)
        let json = try encode(plan)
        let inputs = json["kind"]["programmableTransaction"]["inputs"].arrayValue
        XCTAssertTrue(inputs.allSatisfy { $0["kind"].stringValue == "PURE" })
        XCTAssertEqual(json["gasPayment"]["objects"].arrayValue.count, 2)
    }

    func testGasCoinCanBeToppedUpWithAddressFunds() throws {
        let funds = try funds(4_000_000, [8_000_000])
        let plan = try SuiTransferBuilder.plan(amount: 6_000_000, native: true, budget: budget, gas: funds, token: funds)
        XCTAssertEqual(plan.withdrawal, 3_000_000)
        XCTAssertEqual(plan.payments.count, 1)
        XCTAssertTrue(plan.coins.isEmpty)
        let json = try encode(plan)
        let commands = json["kind"]["programmableTransaction"]["commands"].arrayValue
        XCTAssertEqual(commands[1]["mergeCoins"]["coin"]["kind"].stringValue, "GAS")
    }

    func testAddressOnlyTransferDoesNotCreateZeroWithdrawalOrGasCoin() throws {
        let funds = try funds(20_000_000_000, [])
        let plan = try SuiTransferBuilder.plan(amount: 15_000_000_000, native: true, budget: budget, gas: funds, token: funds)
        XCTAssertEqual(plan.withdrawal, 15_000_000_000)
        XCTAssertTrue(plan.coins.isEmpty)
        XCTAssertTrue(plan.payments.isEmpty)
        let json = try encode(plan)
        XCTAssertEqual(json["gasPayment"]["budget"].stringValue, budget.description)
        XCTAssertEqual(json["expiration"]["kind"].stringValue, "VALID_DURING")
    }

    func testTokenTransferCombinesBalancesAndReservesSeparateSuiGas() throws {
        let gas = try funds(0, [10_000_000])
        let token = try funds(30, [40, 50], type: token)
        let plan = try SuiTransferBuilder.plan(amount: 115, native: false, budget: budget, gas: gas, token: token)
        XCTAssertEqual(plan.withdrawal, 25)
        XCTAssertEqual(plan.coins.count, 2)
        XCTAssertEqual(plan.payments.count, 1)
        XCTAssertTrue(Set(plan.coins.map(\.coinObjectId)).isDisjoint(with: plan.payments.map(\.coinObjectId)))
        XCTAssertEqual(plan.amount, 115)
    }

    func testMaxUsesTotalBalanceMinusGas() throws {
        let funds = try funds(9_619_702_204, [3_000_000_000, 4_000_000_000])
        let plan = try SuiTransferBuilder.plan(amount: nil, native: true, budget: budget, gas: funds, token: funds)
        XCTAssertEqual(BigInt(plan.amount) + budget, funds.total)
        XCTAssertEqual(BigInt(plan.withdrawal) + budget, funds.address)
        XCTAssertEqual(plan.coins.count, 2)
    }

    func testMaxTokenDoesNotSubtractGasFromTokens() throws {
        let gas = try funds(10_000_000, [])
        let token = try funds(30, [40, 50], type: token)
        let plan = try SuiTransferBuilder.plan(amount: nil, native: false, budget: budget, gas: gas, token: token)
        XCTAssertEqual(plan.amount, 120)
        XCTAssertEqual(plan.withdrawal, 30)
    }

    func testRejectsInsufficientTotalBalanceAndZeroAmount() throws {
        let funds = try funds(9_619_702_204, [1_000_000_000])
        for amount: UInt64 in [0, 15_000_000_000] {
            XCTAssertThrowsError(try SuiTransferBuilder.plan(amount: amount, native: true, budget: budget, gas: funds, token: funds))
        }
    }

    func testGasMustBeFundableBeforeCommandsExecute() throws {
        let funds = try funds(3_000_000, [3_000_000])
        XCTAssertThrowsError(try SuiTransferBuilder.plan(amount: 1, native: true, budget: budget, gas: funds, token: funds))
    }

    func testRejectsOverflowInsteadOfTruncatingMaxTransfer() throws {
        let funds = try funds(BigInt(UInt64.max), [UInt64.max])
        XCTAssertThrowsError(try SuiTransferBuilder.plan(amount: nil, native: true, budget: budget, gas: funds, token: funds))
    }

    func testSimulationBudgetReservesTransferAmount() throws {
        let funds = try funds(10_000_000, [10_000_000])
        XCTAssertEqual(SuiTransferBuilder.gasCapacity(amount: 19_000_000, native: true, gas: funds), 1_000_000)
    }

    func testLargeStorageRebateDoesNotEraseComputationBudget() throws {
        let summary = GasCostSummary(computationCost: "100000", storageCost: "1000",
            storageRebate: "10000000", nonRefundableStorageFee: "0")
        XCTAssertEqual(try SuiTransferBuilder.requiredBudget(summary, price: 1000), 1_100_000)
    }

    func testLoadsCoinsAcrossAllPages() async throws {
        let funds = try funds(0, [1, 2])
        var cursors: [String?] = []
        let coins = try await SuiTransferBuilder.loadCoins { cursor in
            cursors.append(cursor)
            return cursor == nil
                ? PaginatedCoins(data: [funds.coins[0]], nextCursor: "second", hasNextPage: true)
                : PaginatedCoins(data: [funds.coins[1]], hasNextPage: false)
        }
        XCTAssertEqual(coins.count, 2)
        XCTAssertEqual(cursors, [nil, "second"])
    }

    func testRejectsRepeatedPaginationCursor() async throws {
        do {
            _ = try await SuiTransferBuilder.loadCoins { _ in
                PaginatedCoins(data: [], nextCursor: "same", hasNextPage: true)
            }
            XCTFail("Expected cursor validation failure")
        } catch { XCTAssertTrue(String(describing: error).contains("cursor")) }
    }

    func testLoadsGraphQLPageInfoCursors() async throws {
        let funds = try funds(0, [1, 2])
        let coins = try await SuiTransferBuilder.loadCoins { cursor in
            PaginatedCoins(data: [funds.coins[cursor == nil ? 0 : 1]],
                pageInfo: PageInfo(endCursor: cursor == nil ? "second" : nil, hasNextPage: cursor == nil))
        }
        XCTAssertEqual(coins.count, 2)
    }

    private func encode(_ plan: SuiTransferBuilder.Plan) throws -> JSON {
        let transaction = try plan.transaction(sender: "0x1", recipient: "0x2", coinType: sui,
            gasPrice: 1000, expiration: .validDuring(minEpoch: 1, maxEpoch: 2,
                minTimestamp: nil, maxTimestamp: nil, chain: [UInt8](repeating: 0, count: 32), nonce: 1))
        // Round-trip the exact transaction that signing uses, then check the JSON
        // sent to GraphQL. This catches lost gas reservations and argument indices.
        let bytes = try transaction.blockData.build()
        let decoded: TransactionData = try Deserializer._struct(Deserializer(data: bytes))
        let serializer = Serializer()
        try decoded.serialize(serializer)
        XCTAssertEqual(serializer.output(), bytes)
        guard case .V1(let data) = decoded else { throw SuiError.customError(message: "Missing V1 transaction") }
        return try JSON(data: JSONEncoder().encode(GraphQLTransactionJSONEncoder.encode(data)))
    }
}
