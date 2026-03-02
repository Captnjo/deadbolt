import SwiftUI
import DeadboltCore

/// P8-013: Native staking view.
/// Shows existing stake accounts and provides basic SOL staking with validator selection.
struct NativeStakeView: View {
    @EnvironmentObject var walletService: WalletService
    @Environment(\.dismiss) private var dismiss

    @State private var stakeAccounts: [StakeAccountInfo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    /// Hardcoded top validators for basic native staking.
    private static let topValidators: [ValidatorInfo] = [
        ValidatorInfo(name: "Jito", voteAccount: "J1to1yufRnoWn81KYg1XkTWzmKjnYSnmE2VY8DGUJ9Qv"),
        ValidatorInfo(name: "Marinade", voteAccount: "mrgn2vsRPXFw7wd2n3RYhGBPurhhrWixmn3JhLEa5Mbo"),
        ValidatorInfo(name: "Laine", voteAccount: "GE6atKoWiQ2pt3zL7N13pjNHjdLVys8LinG8qeJLcAiL"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Text("Native Staking")
                    .font(.headline)

                Spacer()

                Color.clear.frame(width: 24)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Existing stake accounts
                    existingStakesSection

                    Divider()

                    // Top validators
                    validatorsSection
                }
                .padding()
            }

            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                    Text(error)
                        .font(.caption)
                }
                .foregroundStyle(.red)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .frame(minWidth: 450, minHeight: 400)
        .task {
            await loadStakeAccounts()
        }
    }

    // MARK: - Existing Stakes

    private var existingStakesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Stake Accounts")
                .font(.headline)

            if isLoading {
                ProgressView("Loading stake accounts...")
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if stakeAccounts.isEmpty {
                Text("No active stake accounts")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(stakeAccounts, id: \.address) { account in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shortAddress(account.address))
                                .font(.system(.body, design: .monospaced))
                            Text(account.status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(DashboardViewModel.formatSOL(account.lamports) + " SOL")
                            .fontWeight(.medium)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Validators

    private var validatorsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top Validators")
                .font(.headline)

            Text("Native staking creates a stake account delegated to a validator. For liquid staking (instant unstake), use the Stake button on the dashboard.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(Self.topValidators, id: \.voteAccount) { validator in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(validator.name)
                            .fontWeight(.medium)
                        Text(shortAddress(validator.voteAccount))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("Coming soon")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Logic

    private func loadStakeAccounts() async {
        guard walletService.activeWallet != nil else { return }
        isLoading = true

        // Stake accounts would be fetched via RPC getProgramAccounts.
        // For now, show empty list as this requires additional RPC implementation.
        stakeAccounts = []
        isLoading = false
    }

    private func shortAddress(_ address: String) -> String {
        guard address.count > 8 else { return address }
        return "\(address.prefix(4))...\(address.suffix(4))"
    }
}

/// Represents a stake account.
struct StakeAccountInfo {
    let address: String
    let lamports: UInt64
    let status: String // "Active", "Deactivating", "Inactive"
}

/// Represents a validator.
struct ValidatorInfo {
    let name: String
    let voteAccount: String
}
