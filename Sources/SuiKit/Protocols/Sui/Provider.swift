//
//  Provider.swift
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

import BigInt
import SwiftyJSON

/// Common operations exposed by Sui network providers.
public protocol Provider {
    var connection: any ConnectionProtocol { get set }

    func devInspectTransactionBlock(
        transactionBlock: inout TransactionBlock,
        sender: Account,
        gasPrice: Int?,
        epoch: String?
    ) async throws -> DevInspectResults?

    func dryRunTransactionBlock(
        transactionBlock: [UInt8]
    ) async throws -> SuiTransactionBlockResponse

    func signAndExecuteTransactionBlock(
        transactionBlock: inout TransactionBlock,
        signer: Account,
        options: SuiTransactionBlockResponseOptions?,
        requestType: SuiRequestType?
    ) async throws -> SuiTransactionBlockResponse

    func executeTransactionBlock(
        transactionBlock: String,
        signature: String,
        options: SuiTransactionBlockResponseOptions?,
        requestType: SuiRequestType?
    ) async throws -> SuiTransactionBlockResponse

    func executeTransactionBlock(
        transactionBlock: [UInt8],
        signature: String,
        options: SuiTransactionBlockResponseOptions?,
        requestType: SuiRequestType?
    ) async throws -> SuiTransactionBlockResponse

    func getChainIdentifier() async throws -> String

    func getCheckpoints(
        cursor: String?,
        limit: Int?,
        order: SortOrder
    ) async throws -> CheckpointPage

    func getEvents(
        transactionDigest: String
    ) async throws -> PaginatedSuiMoveEvent

    func getLatestCheckpointSequenceNumber() async throws -> String

    func getLoadedChildObjects(
        digest: String
    ) async throws -> [TransactionEffectsModifiedAtVersions]

    func getMoveFunctionArgTypes(
        package: String,
        module: String,
        function: String
    ) async throws -> [SuiMoveFunctionArgType]

    func getNormalizedMoveFunction(
        package: String,
        moduleName: String,
        functionName: String
    ) async throws -> SuiMoveNormalizedFunction?

    func getNormalizedMoveModule(
        package: String,
        module: String
    ) async throws -> SuiMoveNormalizedModule?

    func getNormalizedMoveStruct(
        package: String,
        module: String,
        structure: String
    ) async throws -> SuiMoveNormalizedStruct?

    func getObject(
        objectId: String,
        options: SuiObjectDataOptions?
    ) async throws -> SuiObjectResponse?

    func getProtocolConfig(
        version: String?
    ) async throws -> ProtocolConfig

    func getTotalTransactionBlocks() async throws -> BigInt

    func getTransactionBlock(
        digest: String,
        options: SuiTransactionBlockResponseOptions?
    ) async throws -> SuiTransactionBlockResponse

    func getMultiObjects(
        ids: [ObjectId],
        options: SuiObjectDataOptions?
    ) async throws -> [SuiObjectResponse]

    func multiGetTransactionBlocks(
        digests: [String],
        options: SuiTransactionBlockResponseOptions?
    ) async throws -> [SuiTransactionBlockResponse]

    func tryGetPastObject(
        id: String,
        version: Int,
        options: SuiObjectDataOptions?
    ) async throws -> ObjectRead?

    func tryMultiGetPastObjects(
        objects: [GetPastObjectRequest],
        options: SuiObjectDataOptions?
    ) async throws -> [ObjectRead]

    func getAllBalances(
        account: Account
    ) async throws -> [CoinBalance]

    func getAllCoins(
        account: any PublicKeyProtocol,
        cursor: String?,
        limit: UInt?
    ) async throws -> PaginatedCoins

    func getBalance(
        account: any PublicKeyProtocol,
        coinType: String?
    ) async throws -> CoinBalance

    func getCoinMetadata(
        coinType: String
    ) async throws -> SuiCoinMetadata

    func getCoins(
        account: String,
        coinType: String?,
        cursor: String?,
        limit: UInt?
    ) async throws -> PaginatedCoins

    func getCommitteeInfo(
        epoch: String
    ) async throws -> CommitteeInfo

    func getDynamicFieldObject(
        parentId: String,
        name: String
    ) async throws -> SuiObjectResponse?

    func getDynamicFieldObject(
        parentId: String,
        name: DynamicFieldName
    ) async throws -> SuiObjectResponse?

    func getDynamicFields(
        parentId: String,
        filter: SuiObjectDataFilter?,
        options: SuiObjectDataOptions?,
        limit: Int?,
        cursor: String?
    ) async throws -> DynamicFieldPage

    func info() async throws -> JSON

    func getOwnedObjects(
        owner: String,
        filter: SuiObjectDataFilter?,
        options: SuiObjectDataOptions?,
        cursor: String?,
        limit: Int?
    ) async throws -> PaginatedObjectsResponse

    func getReferenceGasPrice() async throws -> BigInt

    func getStakes(
        owner: String
    ) async throws -> [DelegatedStake]

    func getStakesByIds(
        stakes: [String]
    ) async throws -> [DelegatedStake]

    func totalSupply(_ coinType: String) async throws -> BigInt

    func getValidatorsApy() async throws -> ValidatorApys

    func queryEvents(
        query: SuiEventFilter?,
        cursor: EventId?,
        limit: Int?,
        order: SortOrder?
    ) async throws -> PaginatedSuiMoveEvent

    func queryTransactionBlocks(
        cursor: String?,
        limit: Int?,
        order: SortOrder?,
        filter: TransactionFilter?,
        options: SuiTransactionBlockResponseOptions?
    ) async throws -> PaginatedTransactionResponse

    func resolveNameserviceAddress(name: String) async throws -> AccountAddress

    func waitForTransaction(
        tx: String,
        options: SuiTransactionBlockResponseOptions?
    ) async throws -> SuiTransactionBlockResponse
}
