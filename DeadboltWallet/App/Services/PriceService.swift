import Foundation
import DeadboltCore

/// Fetches USD prices via CoinGecko free API + Jupiter Price API v2
actor PriceService {
    private let httpClient = HTTPClient()

    private let usdcMint = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
    private let usdtMint = "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"

    private struct CoinGeckoResponse: Decodable {
        let solana: PriceData
        struct PriceData: Decodable {
            let usd: Double
        }
    }

    /// Fetch SOL/USD price from CoinGecko (free, no API key required)
    func fetchSOLPrice() async throws -> Double {
        let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=solana&vs_currencies=usd")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(CoinGeckoResponse.self, from: data)
        return response.solana.usd
    }

    /// Fetch token/USD price for a given mint using Jupiter Price API v2
    func fetchTokenPrice(mint: String, decimals: Int) async throws -> Double {
        // Stablecoins are always $1
        if mint == usdcMint || mint == usdtMint {
            return 1.0
        }

        // Use Jupiter Price API v2 (requires API key)
        var components = URLComponents(string: "https://api.jup.ag/price/v2")!
        components.queryItems = [URLQueryItem(name: "ids", value: mint)]

        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let response = try JSONDecoder().decode(JupiterPriceResponse.self, from: data)

        guard let tokenData = response.data[mint],
              let priceStr = tokenData.price,
              let price = Double(priceStr) else {
            throw SolanaError.priceUnavailable(mint)
        }
        return price
    }
}

private struct JupiterPriceResponse: Decodable {
    let data: [String: TokenPrice]
    struct TokenPrice: Decodable {
        let price: String?
    }
}
