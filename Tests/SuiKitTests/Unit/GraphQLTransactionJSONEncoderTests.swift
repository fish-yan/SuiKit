//
//  GraphQLTransactionJSONEncoderTests.swift
//  SuiKitTests
//

import Foundation
import SwiftyJSON
import XCTest
@testable import SuiKit

final class GraphQLTransactionJSONEncoderTests: XCTestCase {
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
}
