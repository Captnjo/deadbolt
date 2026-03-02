import Foundation
import SwiftUI
import DeadboltCore

@MainActor
final class DashboardViewModel: ObservableObject {

    /// Format a SOL amount for display (up to 9 decimals, trimmed)
    static func formatSOL(_ lamports: UInt64) -> String {
        let sol = Double(lamports) / 1_000_000_000.0
        if sol == 0 { return "0" }
        // Show up to 4 decimal places
        let formatted = String(format: "%.4f", sol)
        // Trim trailing zeros but keep at least one decimal
        return trimTrailingZeros(formatted)
    }

    /// Format USD value
    static func formatUSD(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    /// Format a token balance for display
    static func formatTokenAmount(_ amount: Double) -> String {
        if amount == 0 { return "0" }
        if amount >= 1_000_000 {
            return String(format: "%.0f", amount)
        } else if amount >= 1 {
            return trimTrailingZeros(String(format: "%.2f", amount))
        } else {
            return trimTrailingZeros(String(format: "%.6f", amount))
        }
    }

    private static func trimTrailingZeros(_ s: String) -> String {
        guard s.contains(".") else { return s }
        var result = s
        while result.hasSuffix("0") { result.removeLast() }
        if result.hasSuffix(".") { result.removeLast() }
        return result
    }
}
