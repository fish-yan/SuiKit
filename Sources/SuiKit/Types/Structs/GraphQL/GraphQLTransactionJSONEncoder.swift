//
//  GraphQLTransactionJSONEncoder.swift
//  SuiKit
//

import Foundation

enum GraphQLTransactionJSONEncoder {
    static func encode(_ data: TransactionDataV1) throws -> SuiJSON {
        var transaction: [String: SuiJSON] = [
            "version": .number(1),
            "kind": try encode(data.kind),
            "sender": .string(data.sender.hex()),
            "gasPayment": encode(data.gasData, fallbackOwner: data.sender),
            "expiration": encode(data.expiration)
        ]
        if data.gasData.payment?.isEmpty == true {
            transaction.removeValue(forKey: "gasPayment")
        }
        return .object(transaction)
    }

    static func encode(
        _ builder: SerializedTransactionDataBuilder,
        sender: AccountAddress,
        gasPrice: Int?
    ) throws -> SuiJSON {
        let programmableTransaction = ProgrammableTransaction(
            inputs: builder.inputs.compactMap { input in
                guard case .callArg(let argument) = input.value else { return nil }
                return argument
            },
            transactions: builder.transactions
        )
        var transaction: [String: SuiJSON] = [
            "version": .number(1),
            "kind": try encode(.programmableTransaction(programmableTransaction)),
            "sender": .string(sender.hex()),
            "expiration": encode(builder.expiration ?? .none)
        ]
        if let gasPrice {
            transaction["gasPayment"] = .object([
                "owner": .string(sender.hex()),
                "price": .string(String(gasPrice))
            ])
        }
        return .object(transaction)
    }

    private static func encode(_ kind: SuiTransactionBlockKind) throws -> SuiJSON {
        guard case .programmableTransaction(let programmableTransaction) = kind else {
            throw SuiError.customError(
                message: "GraphQL simulation currently supports programmable transactions only"
            )
        }
        return .object([
            "kind": .string("PROGRAMMABLE_TRANSACTION"),
            "programmableTransaction": .object([
                "inputs": .array(try programmableTransaction.inputs.map(encode)),
                "commands": .array(try programmableTransaction.transactions.map(encode))
            ])
        ])
    }

    private static func encode(_ input: Input) throws -> SuiJSON {
        switch input.inputType {
        case .pure(let pure):
            return .object([
                "kind": .string("PURE"),
                "pure": .string(Data(pure.value).base64EncodedString())
            ])
        case .object(let object):
            return encode(object)
        }
    }

    private static func encode(_ object: ObjectArg) -> SuiJSON {
        switch object {
        case .immOrOwned(let object):
            return encode(object.ref, kind: "IMMUTABLE_OR_OWNED")
        case .receiving(let object):
            return encode(object.ref, kind: "RECEIVING")
        case .shared(let object):
            return .object([
                "kind": .string("SHARED"),
                "objectId": .string(object.objectId),
                "version": .string(String(object.initialSharedVersion)),
                "mutable": .bool(object.mutable),
                "mutability": .string(object.mutable ? "MUTABLE" : "IMMUTABLE")
            ])
        }
    }

    private static func encode(_ reference: SuiObjectRef, kind: String) -> SuiJSON {
        .object([
            "kind": .string(kind),
            "objectId": .string(reference.objectId),
            "version": .string(reference.version),
            "digest": .string(reference.digest)
        ])
    }

    private static func encode(_ transaction: SuiTransaction) throws -> SuiJSON {
        switch transaction {
        case .moveCall(let call):
            return .object([
                "moveCall": .object([
                    "package": .string(call.target.address.hex()),
                    "module": .string(call.target.module),
                    "function": .string(call.target.name),
                    "typeArguments": .array(try call.typeArguments.map { .string(try typeName($0)) }),
                    "arguments": .array(call.arguments.map(encode))
                ])
            ])
        case .transferObjects(let transfer):
            return .object([
                "transferObjects": .object([
                    "objects": .array(transfer.objects.map(encode)),
                    "address": encode(transfer.address)
                ])
            ])
        case .splitCoins(let split):
            return .object([
                "splitCoins": .object([
                    "coin": encode(split.coin),
                    "amounts": .array(split.amounts.map(encode))
                ])
            ])
        case .mergeCoins(let merge):
            return .object([
                "mergeCoins": .object([
                    "coin": encode(merge.destination),
                    "coinsToMerge": .array(merge.sources.map(encode))
                ])
            ])
        case .publish(let publish):
            return .object([
                "publish": .object([
                    "modules": .array(publish.modules.map { .string(Data($0).base64EncodedString()) }),
                    "dependencies": .array(publish.dependencies.map { .string($0.hex()) })
                ])
            ])
        case .makeMoveVec(let vector):
            var value: [String: SuiJSON] = [
                "elements": .array(vector.objects.map(encode))
            ]
            if let type = vector.type {
                value["type"] = .string(type.description)
            }
            return .object(["makeMoveVector": .object(value)])
        case .upgrade(let upgrade):
            return .object([
                "upgrade": .object([
                    "modules": .array(upgrade.modules.map { .string(Data($0).base64EncodedString()) }),
                    "dependencies": .array(upgrade.dependencies.map(SuiJSON.string)),
                    "package": .string(upgrade.packageId),
                    "ticket": encode(upgrade.ticket)
                ])
            ])
        }
    }

    private static func encode(_ argument: TransactionArgument) -> SuiJSON {
        switch argument {
        case .gasCoin:
            return .object(["kind": .string("GAS")])
        case .input(let input):
            return .object([
                "kind": .string("INPUT"),
                "input": .number(Double(input.index))
            ])
        case .result(let result):
            return .object([
                "kind": .string("RESULT"),
                "result": .number(Double(result.index))
            ])
        case .nestedResult(let result):
            return .object([
                "kind": .string("RESULT"),
                "result": .number(Double(result.index)),
                "subresult": .number(Double(result.resultIndex))
            ])
        }
    }

    private static func encode(_ gas: SuiGasData, fallbackOwner: AccountAddress) -> SuiJSON {
        .object([
            "objects": .array((gas.payment ?? []).map { reference in
                .object([
                    "objectId": .string(reference.objectId),
                    "version": .string(reference.version),
                    "digest": .string(reference.digest)
                ])
            }),
            "owner": .string((gas.owner ?? fallbackOwner).hex()),
            "price": gas.price.map(SuiJSON.string) ?? .null,
            "budget": gas.budget.map(SuiJSON.string) ?? .null
        ])
    }

    private static func encode(_ expiration: TransactionExpiration) -> SuiJSON {
        switch expiration {
        case .none:
            return .object(["kind": .string("NONE")])
        case .epoch(let epoch):
            return .object([
                "kind": .string("EPOCH"),
                "epoch": .string(String(epoch))
            ])
        }
    }

    private static func typeName(_ type: TypeTag) throws -> String {
        if let structure = type.value as? StructTag {
            return try structure.toString()
        }
        return try type.toString()
    }
}
