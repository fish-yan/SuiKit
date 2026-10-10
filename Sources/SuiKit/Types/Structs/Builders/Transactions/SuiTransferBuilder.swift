import BigInt
import Foundation

/// Builds wallet transfers using both Coin objects and address balances.
/// Fee estimation and signing must use this same builder, rather than reserving
/// the full transfer amount with `transferFromAddressBalance`.
public struct SuiTransferBuilder {
    private let provider: Provider

    public init(provider: Provider) {
        self.provider = provider
    }

    /// Returns a fully funded, successfully simulated transaction. Nothing is signed or submitted.
    /// - Parameter amount: Amount in base units, or nil to send all (reserving gas for SUI).
    /// - Parameter gasBudget: Optional explicit budget. Otherwise estimated with checks enabled.
    public func build(
        sender: String,
        recipient: String,
        amount: UInt64?,
        coinType: String = "0x2::sui::SUI",
        gasBudget: UInt64? = nil
    ) async throws -> TransactionBlock {
        if amount == 0 { throw Self.error("Transfer amount must be positive; use nil for send-all") }
        let type = try StructTag.fromStr(coinType).toString()
        let suiType = try StructTag.fromStr("0x2::sui::SUI").toString()
        _ = try AccountAddress.fromHex(sender)
        _ = try AccountAddress.fromHex(recipient)
        let native = type == suiType
        let gas = try await loadFunds(owner: sender, coinType: suiType)
        let token = native ? gas : try await loadFunds(owner: sender, coinType: type)
        let referencePrice = try await provider.getReferenceGasPrice()
        guard let gasPrice = UInt64(referencePrice.description), gasPrice > 0 else {
            throw Self.error("Invalid reference gas price")
        }
        let state = try await provider.info()
        guard let epoch = state["epoch"].uInt64, epoch < UInt64.max,
              let chain = try await provider.getGenesisCheckpointDigest().base58DecodedData,
              chain.count == 32 else {
            throw Self.error("Missing epoch or genesis checkpoint digest")
        }
        let expiration = TransactionExpiration.validDuring(
            minEpoch: epoch, maxEpoch: epoch + 1, minTimestamp: nil, maxTimestamp: nil,
            chain: [UInt8](chain), nonce: UInt32.random(in: .min ... .max)
        )
        let capacity = Self.gasCapacity(amount: amount, native: native, gas: gas)
        var budget = gasBudget.map { BigInt($0) } ?? min(capacity, 50_000_000)
        var successful: TransactionBlock?
        var reducedBudget = false

        // A lower budget can change the gas source and the number of merged coins.
        // Simulate that final shape too, including the resolved send-all amount.
        for _ in 0..<8 {
            let plan = try Self.plan(amount: amount, native: native, budget: budget, gas: gas, token: token)
            let transaction = try plan.transaction(
                sender: sender, recipient: recipient, coinType: type,
                gasPrice: gasPrice, expiration: expiration
            )
            let response = try await provider.simulateTransaction(
                transaction: transaction.blockData.buildTransactionData(),
                checksEnabled: true, doGasSelection: false
            )
            guard let effects = response.effects else {
                throw Self.error("Missing simulated transaction effects")
            }
            if effects.status.status != .success {
                let message = effects.status.error ?? "Unknown simulation failure"
                guard gasBudget == nil, message.contains("InsufficientGas") else {
                    throw Self.error(message)
                }
                let increased = min(capacity, budget * 2)
                guard increased > budget else {
                    if let successful { return successful }
                    throw Self.error(message)
                }
                budget = increased
                reducedBudget = true
                continue
            }
            successful = transaction
            if gasBudget != nil { return transaction }
            let required = try Self.requiredBudget(effects.gasUsed, price: gasPrice)
            if required <= budget && (reducedBudget || required == budget) { return transaction }
            if required > capacity { return transaction }
            reducedBudget = required < budget || reducedBudget
            budget = required
        }
        guard let successful else { throw Self.error("Unable to estimate transfer gas") }
        return successful
    }

    private func loadFunds(owner: String, coinType: String) async throws -> Funds {
        let balance = try await provider.getBalance(owner: owner, coinType: coinType)
        guard let value = balance.addressBalance, let address = BigInt(value), address >= 0 else {
            throw Self.error("Provider must return addressBalance separately from Coin object balance")
        }
        let coins = try await Self.loadCoins { cursor in
            try await provider.getCoins(owner: owner, coinType: coinType, cursor: cursor, limit: 50)
        }
        return try Funds(address: address, coins: coins)
    }

    static func loadCoins(fetch: (String?) async throws -> PaginatedCoins) async throws -> [CoinStruct] {
        var coins: [CoinStruct] = []
        var cursor: String?
        var cursors = Set<String>()
        var ids = Set<String>()
        repeat {
            let page = try await fetch(cursor)
            for coin in page.data {
                let id = try Inputs.normalizeSuiAddress(value: coin.coinObjectId)
                guard ids.insert(id).inserted else { throw error("Duplicate Coin object in pagination") }
                coins.append(coin)
            }
            guard page.hasNextPage == true || page.pageInfo?.hasNextPage == true else { return coins }
            guard let next = page.nextCursor ?? page.pageInfo?.endCursor,
                  cursors.insert(next).inserted else { throw error("Invalid Coin pagination cursor") }
            cursor = next
        } while true
    }

    struct Funds {
        let address: BigInt
        let coins: [CoinStruct]
        let coinBalance: BigInt
        var total: BigInt { address + coinBalance }

        init(address: BigInt, coins: [CoinStruct]) throws {
            guard address >= 0 else { throw SuiTransferBuilder.error("Invalid address balance") }
            self.address = address
            self.coins = coins
            coinBalance = try coins.reduce(BigInt.zero) { total, coin in
                guard let value = BigInt(coin.balance), value >= 0 else {
                    throw SuiTransferBuilder.error("Invalid Coin object balance")
                }
                return total + value
            }
        }
    }

    static func gasCapacity(amount: UInt64?, native: Bool, gas: Funds) -> BigInt {
        var capacity = max(gas.address, gas.coinBalance)
        if native, let amount { capacity = min(capacity, gas.total - BigInt(amount)) }
        return min(capacity, BigInt(TransactionConstants.MAX_GAS))
    }

    static func plan(amount: UInt64?, native: Bool, budget: BigInt, gas: Funds, token: Funds) throws -> Plan {
        guard budget > 0 else { throw error("Insufficient SUI to reserve gas") }
        let transfer = amount.map { BigInt($0) } ?? (token.total - (native ? budget : 0))
        guard transfer > 0, transfer <= token.total else { throw error("Insufficient transfer balance or zero amount") }
        let requiredSui = budget + (native ? transfer : 0)
        guard requiredSui <= gas.total else { throw error("Insufficient SUI for transfer and gas") }
        var payments: [CoinStruct] = []
        var inputs: [CoinStruct] = []
        let withdrawal: BigInt
        if gas.address >= budget {
            let available = token.address - (native ? budget : 0)
            inputs = select(token.coins, target: transfer - available)
            withdrawal = max(0, transfer - sum(inputs))
            guard withdrawal <= available else { throw error("Insufficient Coin object balance") }
        } else {
            payments = select(gas.coins, target: requiredSui)
            guard sum(payments) >= budget else { throw error("Insufficient Coin objects to fund gas before execution") }
            if native {
                withdrawal = max(0, requiredSui - sum(payments))
            } else {
                inputs = select(token.coins, target: transfer - token.address)
                withdrawal = max(0, transfer - sum(inputs))
            }
            guard withdrawal <= token.address else { throw error("Insufficient address balance") }
        }
        guard payments.count <= TransactionConstants.MAX_GAS_OBJECTS,
              inputs.count + payments.count <= 256 else {
            throw error("Too many Coin objects for one transfer; consolidate coins first")
        }
        guard let value = UInt64(transfer.description), let reserved = UInt64(withdrawal.description),
              let gasBudget = UInt64(budget.description) else { throw error("Transfer amount exceeds UInt64") }
        return Plan(amount: value, withdrawal: reserved, budget: gasBudget, native: native, coins: inputs, payments: payments)
    }

    private static func select(_ coins: [CoinStruct], target: BigInt) -> [CoinStruct] {
        var selected: [CoinStruct] = []
        var balance = BigInt.zero
        for coin in coins where balance < target {
            guard let value = BigInt(coin.balance), value > 0 else { continue }
            selected.append(coin)
            balance += value
        }
        return selected
    }

    private static func sum(_ coins: [CoinStruct]) -> BigInt {
        coins.reduce(BigInt.zero) { $0 + (BigInt($1.balance) ?? 0) }
    }

    static func requiredBudget(_ summary: GasCostSummary, price: UInt64) throws -> BigInt {
        guard let computation = BigInt(summary.computationCost), let storage = BigInt(summary.storageCost),
              let rebate = BigInt(summary.storageRebate), computation >= 0, storage >= 0, rebate >= 0 else {
            throw error("Invalid simulated gas summary")
        }
        let base = computation + BigInt(price) * BigInt(TransactionConstants.GAS_SAFE_OVERHEAD)
        return max(base, base + storage - rebate)
    }

    struct Plan {
        let amount: UInt64
        let withdrawal: UInt64
        let budget: UInt64
        let native: Bool
        let coins: [CoinStruct]
        let payments: [CoinStruct]

        func transaction(sender: String, recipient: String, coinType: String, gasPrice: UInt64,
                         expiration: TransactionExpiration) throws -> TransactionBlock {
            let transaction = try TransactionBlock()
            try transaction.setSender(sender: sender)
            transaction.setGasPrice(price: BigInt(gasPrice))
            transaction.setGasBudget(price: BigInt(budget))
            try transaction.setGasPayment(payments: payments.map { $0.toSuiObjectRef() })
            transaction.setExpiration(expiration: payments.isEmpty ? expiration : .none)
            var sources: [TransactionArgument] = []
            for coin in coins {
                sources.append(try transaction.objectRef(
                    objectArg: .immOrOwned(ImmOrOwned(ref: coin.toSuiObjectRef()))
                ).toTransactionArgument())
            }
            let usesGasCoin = native && !payments.isEmpty
            var destination: TransactionArgument? = usesGasCoin ? .gasCoin : (sources.isEmpty ? nil : sources.removeFirst())
            let needsSplit = destination != nil
            if withdrawal > 0 {
                let input = try transaction.withdrawal(amount: withdrawal, coinType: coinType)
                let coin = try transaction.moveCall(target: "0x2::coin::redeem_funds",
                    arguments: [.input(input)], typeArguments: [coinType])[0]
                if destination == nil { destination = coin } else { sources.append(coin) }
            }
            guard let destination else { throw SuiTransferBuilder.error("No transfer funds selected") }
            if !sources.isEmpty { _ = try transaction.mergeCoin(destination: destination, sources: sources) }
            let output: TransactionArgument
            if needsSplit {
                let serializer = Serializer()
                try Serializer.u64(serializer, amount)
                output = try transaction.splitCoin(coin: destination, amounts: [transaction.pure(data: serializer.output())])
            } else {
                output = destination
            }
            _ = try transaction.transferObject(objects: [output], address: recipient)
            // An owned input still contains the change after splitting; explicitly
            // return it. A gas coin's remainder is returned by the protocol.
            if needsSplit && !usesGasCoin {
                _ = try transaction.transferObject(objects: [destination], address: sender)
            }
            return transaction
        }
    }

    private static func error(_ message: String) -> SuiError { .customError(message: message) }
}
