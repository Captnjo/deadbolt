import Foundation

/// Token metadata from tokens.txt (CSV: mint,name,decimals,price)
public struct TokenDefinition: Sendable, Identifiable {
    public let mint: String
    public let name: String
    public let decimals: Int
    public var cachedPrice: Double

    public var id: String { mint }

    public init(mint: String, name: String, decimals: Int, cachedPrice: Double = 0) {
        self.mint = mint
        self.name = name
        self.decimals = decimals
        self.cachedPrice = cachedPrice
    }

    /// Parse a tokens.txt line: "mint,name,decimals,price"
    public static func parse(line: String) -> TokenDefinition? {
        let parts = line.split(separator: ",", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.count >= 3 else { return nil }
        guard let decimals = Int(parts[2]) else { return nil }
        let price = parts.count >= 4 ? Double(parts[3]) ?? 0 : 0
        return TokenDefinition(
            mint: parts[0],
            name: parts[1],
            decimals: decimals,
            cachedPrice: price
        )
    }
}

/// On-chain token balance combined with definition and USD pricing
public struct TokenBalance: Sendable, Identifiable {
    public let definition: TokenDefinition
    public let rawAmount: UInt64
    public let uiAmount: Double
    public var usdPrice: Double
    public var usdValue: Double { uiAmount * usdPrice }

    public var id: String { definition.mint }

    public init(definition: TokenDefinition, rawAmount: UInt64, uiAmount: Double, usdPrice: Double) {
        self.definition = definition
        self.rawAmount = rawAmount
        self.uiAmount = uiAmount
        self.usdPrice = usdPrice
    }
}
