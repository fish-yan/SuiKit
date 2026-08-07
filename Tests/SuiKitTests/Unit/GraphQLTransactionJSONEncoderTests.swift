//
//  GraphQLTransactionJSONEncoderTests.swift
//  SuiKitTests
//

import Foundation
import SwiftyJSON
import XCTest
@testable import SuiKit

final class GraphQLTransactionJSONEncoderTests: XCTestCase {
    func testAddressBalanceMaxTransferStartsWithAResolvableWithdrawal() throws {
        let transaction = try TransactionBlock()
        _ = try transaction.transferMaxFromAddressBalance(toAddress: "0x2")

        XCTAssertEqual(transaction.blockData.builder.inputs.count, 2)
        guard case .callArg(let callArgument) = transaction.blockData.builder.inputs[0].value,
              case .fundsWithdrawal(let withdrawal) = callArgument.inputType
        else {
            return XCTFail("Expected an address-balance withdrawal input")
        }
        XCTAssertEqual(withdrawal.amount, 1)
        XCTAssertEqual(transaction.blockData.builder.transactions.count, 2)
    }

    func testProgrammableTransactionUsesGRPCJSONShape() throws {
        let sender = try AccountAddress.fromHex("0x1")
        let object = SuiObjectRef(
            objectId: "0x2",
            version: "3",
            digest: "11111111111111111111111111111111"
        )
        let transaction = TransactionDataV1(
            kind: .programmableTransaction(
                ProgrammableTransaction(
                    inputs: [
                        Input(type: .object(.immOrOwned(ImmOrOwned(ref: object)))),
                        Input(type: .pure(PureCallArg(value: [0, 1, 2])))
                    ],
                    transactions: [
                        .transferObjects(
                            TransferObjectsTransaction(
                                objects: [.input(TransactionBlockInput(index: 0))],
                                address: .input(TransactionBlockInput(index: 1))
                            )
                        )
                    ]
                )
            ),
            sender: sender,
            gasData: SuiGasData(
                payment: [object],
                owner: sender,
                price: "1000",
                budget: "1000000"
            ),
            expiration: .none
        )

        let encoded = try GraphQLTransactionJSONEncoder.encode(transaction)
        let data = try JSONEncoder().encode(encoded)
        let json = try JSON(data: data)

        XCTAssertEqual(json["version"].intValue, 1)
        XCTAssertEqual(json["kind"]["kind"].stringValue, "PROGRAMMABLE_TRANSACTION")
        XCTAssertEqual(
            json["kind"]["programmableTransaction"]["inputs"][0]["kind"].stringValue,
            "IMMUTABLE_OR_OWNED"
        )
        XCTAssertEqual(
            json["kind"]["programmableTransaction"]["inputs"][1]["pure"].stringValue,
            Data([0, 1, 2]).base64EncodedString()
        )
        let command = json["kind"]["programmableTransaction"]["commands"][0]
        XCTAssertEqual(command["transferObjects"]["address"]["input"].intValue, 1)
        XCTAssertEqual(json["gasPayment"]["price"].stringValue, "1000")
        XCTAssertEqual(json["expiration"]["kind"].stringValue, "NONE")
    }

    func testBCSTransactionCanBeDecodedAndEncodedForSimulation() throws {
        let sender = try AccountAddress.fromHex("0x1")
        let transaction = TransactionData.V1(
            TransactionDataV1(
                kind: .programmableTransaction(
                    ProgrammableTransaction(inputs: [], transactions: [])
                ),
                sender: sender,
                gasData: SuiGasData(
                    payment: [],
                    owner: sender,
                    price: "1000",
                    budget: "1000000"
                ),
                expiration: .epoch(42)
            )
        )
        let serializer = Serializer()
        try Serializer._struct(serializer, value: transaction)
        let decoded: TransactionData = try Deserializer._struct(
            Deserializer(data: serializer.output())
        )
        guard case .V1(let versionOne) = decoded else {
            return XCTFail("Expected a version one transaction")
        }

        let encoded = try GraphQLTransactionJSONEncoder.encode(versionOne)
        let data = try JSONEncoder().encode(encoded)
        let json = try JSON(data: data)

        XCTAssertEqual(json["sender"].stringValue, sender.hex())
        XCTAssertEqual(json["expiration"]["kind"].stringValue, "EPOCH")
        XCTAssertEqual(json["expiration"]["epoch"].stringValue, "42")
    }

    func testAddressBalanceTransactionUsesGRPCJSONShape() throws {
        let sender = try AccountAddress.fromHex("0x1")
        let chain = Array(UInt8(0)...UInt8(31))
        let transaction = TransactionDataV1(
            kind: .programmableTransaction(
                ProgrammableTransaction(
                    inputs: [
                        Input(type: .fundsWithdrawal(
                            FundsWithdrawal(
                                amount: 100_000_000,
                                coinType: try TypeTag(stringValue: "0x2::sui::SUI")
                            )
                        ))
                    ],
                    transactions: []
                )
            ),
            sender: sender,
            gasData: SuiGasData(
                payment: [],
                owner: sender,
                price: "1000",
                budget: "1000000"
            ),
            expiration: .validDuring(
                minEpoch: 10,
                maxEpoch: 10,
                minTimestamp: nil,
                maxTimestamp: nil,
                chain: chain,
                nonce: 42
            )
        )

        let encoded = try GraphQLTransactionJSONEncoder.encode(transaction)
        let data = try JSONEncoder().encode(encoded)
        let json = try JSON(data: data)

        let input = json["kind"]["programmableTransaction"]["inputs"][0]
        XCTAssertEqual(input["kind"].stringValue, "FUNDS_WITHDRAWAL")
        XCTAssertEqual(input["fundsWithdrawal"]["amount"].stringValue, "100000000")
        XCTAssertEqual(
            input["fundsWithdrawal"]["coinType"].stringValue,
            "0x0000000000000000000000000000000000000000000000000000000000000002::sui::SUI"
        )
        XCTAssertEqual(input["fundsWithdrawal"]["source"].stringValue, "SENDER")
        XCTAssertNil(json["gasPayment"].dictionary)
        XCTAssertEqual(json["expiration"]["kind"].stringValue, "VALID_DURING")
        XCTAssertEqual(json["expiration"]["minEpoch"].stringValue, "10")
        XCTAssertEqual(json["expiration"]["epoch"].stringValue, "10")
        XCTAssertEqual(json["expiration"]["chain"].stringValue, chain.base58EncodedString)
        XCTAssertEqual(json["expiration"]["nonce"].intValue, 42)
    }
}
