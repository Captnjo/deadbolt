import Foundation
import DeadboltCore

/// Tracks transaction confirmation status from submission through finalization.
@MainActor
public final class ConfirmationTracker: ObservableObject {
    public enum Status: Equatable {
        case submitting
        case submitted(signature: String)
        case confirmed(signature: String)
        case finalized(signature: String)
        case failed(error: String)
    }

    @Published public var status: Status = .submitting

    private let rpcClient: SolanaRPCClient
    private let jitoClient: JitoClient
    private let pollInterval: TimeInterval
    private let timeout: TimeInterval

    public init(
        rpcClient: SolanaRPCClient,
        jitoClient: JitoClient = JitoClient(),
        pollInterval: TimeInterval = 2.0,
        timeout: TimeInterval = 60.0
    ) {
        self.rpcClient = rpcClient
        self.jitoClient = jitoClient
        self.pollInterval = pollInterval
        self.timeout = timeout
    }

    /// Begin tracking a submitted transaction signature.
    public func track(signature: String) async {
        status = .submitted(signature: signature)

        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            do {
                let statuses = try await rpcClient.getSignatureStatuses(signatures: [signature])

                if let sigStatus = statuses.first, let s = sigStatus {
                    if s.err != nil {
                        status = .failed(error: "Transaction failed on-chain")
                        return
                    }

                    switch s.confirmationStatus {
                    case "finalized":
                        status = .finalized(signature: signature)
                        return
                    case "confirmed":
                        status = .confirmed(signature: signature)
                        // Keep polling until finalized
                    default:
                        break // processed or nil — keep polling
                    }
                }
            } catch {
                // Network errors during polling are transient — keep trying
            }

            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }

        // Timeout — check if we at least got confirmed
        if case .confirmed = status {
            // Confirmed but not finalized within timeout — that's OK
            return
        }
        status = .failed(error: "Transaction confirmation timed out")
    }

    /// Track a Jito bundle by polling getBundleStatuses for the actual transaction signature,
    /// then tracking that signature via standard RPC polling.
    public func trackBundle(bundleId: String) async {
        status = .submitted(signature: bundleId)

        let deadline = Date().addingTimeInterval(timeout)

        // Phase 1: Poll Jito for the bundle status to get the real transaction signature
        while Date() < deadline {
            do {
                let statuses = try await jitoClient.getBundleStatuses(bundleIds: [bundleId])

                if let bundleStatus = statuses.first {
                    switch bundleStatus.confirmationStatus {
                    case "Landed":
                        // Bundle landed — extract the first transaction signature and track via RPC
                        if let txSignature = bundleStatus.transactions.first {
                            await track(signature: txSignature)
                            return
                        }
                        // Landed but no signatures — treat as confirmed
                        status = .confirmed(signature: bundleId)
                        return
                    case "Failed", "Invalid":
                        status = .failed(error: "Jito bundle \(bundleStatus.confirmationStatus.lowercased())")
                        return
                    default:
                        break // "Pending" or unknown — keep polling
                    }
                }
            } catch {
                // Network errors during polling are transient — keep trying
            }

            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }

        // Timeout waiting for bundle status
        status = .failed(error: "Bundle confirmation timed out")
    }
}
