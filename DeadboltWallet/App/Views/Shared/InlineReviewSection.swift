import SwiftUI
import DeadboltCore

// Brand colors imported from BrandTheme.swift via Brand enum
private let solarFlare = Brand.solarFlare
private let cryptoGreen = Brand.cryptoGreen
private let steelGray = Brand.steelGray

/// Shared inline review/confirm component used by all unified flows.
/// Handles three visual states: reviewing (preview + buttons), confirming (progress),
/// and done (finalized).
struct InlineReviewSection: View {
    let fees: TransactionFees?
    let simulationStatus: TransactionPreviewView.SimulationStatus
    let actionDescription: String
    @ObservedObject var confirmationTracker: ConfirmationTracker
    @ObservedObject var signerLoader: SignerLoader
    let onConfirm: () -> Void
    let onEdit: () -> Void
    let onDone: () -> Void

    /// Whether we are in the confirming phase (transaction submitted).
    let isConfirming: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.bottom, 12)

            if isConfirming {
                confirmingContent
            } else {
                reviewContent
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Review Content

    private var reviewContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review")
                .font(.headline)

            // Action
            infoRow("Action", actionDescription)

            // Fee breakdown
            if let fees {
                Divider()
                feeSection(fees)
            }

            // Simulation status
            Divider()
            simulationBadge

            // Buttons
            HStack(spacing: 12) {
                Button("Edit") {
                    onEdit()
                }
                .buttonStyle(.bordered)

                Button("Confirm") {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .tint(cryptoGreen)
                .disabled(fees == nil)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, 4)
        }
    }

    // MARK: - Confirming Content

    private var confirmingContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Hardware wallet prompt
            if let prompt = signerLoader.hardwareWalletPrompt {
                HStack(spacing: 8) {
                    Image(systemName: "cpu")
                        .symbolEffect(.pulse)
                    Text(prompt)
                        .fontWeight(.medium)
                }
                .foregroundStyle(solarFlare)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(solarFlare.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Confirmation tracker
            ConfirmationView(tracker: confirmationTracker)

            // Done / Close button
            if case .finalized = confirmationTracker.status {
                Button("Done") {
                    onDone()
                }
                .buttonStyle(.borderedProminent)
                .tint(cryptoGreen)
                .frame(maxWidth: .infinity, alignment: .trailing)
            } else if case .failed = confirmationTracker.status {
                Button("Close") {
                    onDone()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    // MARK: - Fee Section

    private func feeSection(_ fees: TransactionFees) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            infoRow("Base Fee", "~\(formatSOL(Double(fees.baseFee) / 1e9)) SOL")
            if fees.priorityFee > 0 {
                infoRow("Priority Fee", "~\(formatSOL(Double(fees.priorityFee) / 1e9)) SOL")
            }
            if fees.tipAmount > 0 {
                infoRow("Jito Tip", "\(formatSOL(Double(fees.tipAmount) / 1e9)) SOL")
            }
            infoRow("Total Fee", "~\(formatSOL(fees.totalSOL)) SOL")
        }
    }

    // MARK: - Simulation Badge

    private var simulationBadge: some View {
        HStack {
            Text("Simulation:")
                .foregroundStyle(.secondary)
            switch simulationStatus {
            case .pending:
                ProgressView()
                    .controlSize(.small)
                Text("Simulating...")
                    .foregroundStyle(steelGray)
            case .success(let cu):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(cryptoGreen)
                Text("Will succeed (\(cu) CU)")
            case .failed(let error):
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text(error)
            case .skipped:
                Image(systemName: "minus.circle")
                    .foregroundStyle(steelGray)
                Text("Skipped (hardware wallet)")
            }
        }
        .font(.caption)
    }

    // MARK: - Helpers

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
        }
    }

    private func formatSOL(_ sol: Double) -> String {
        DashboardViewModel.formatSOL(UInt64(max(0, sol) * 1_000_000_000))
    }
}
