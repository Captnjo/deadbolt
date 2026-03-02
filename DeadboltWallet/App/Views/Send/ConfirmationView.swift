import SwiftUI
import DeadboltCore

struct ConfirmationView: View {
    @ObservedObject var tracker: ConfirmationTracker

    var body: some View {
        VStack(spacing: 16) {
            switch tracker.status {
            case .submitting:
                statusRow(icon: "arrow.up.circle", color: .blue, text: "Submitting transaction...", isActive: true)

            case .submitted(let sig):
                statusRow(icon: "checkmark.circle.fill", color: .green, text: "Submitted", isActive: false)
                statusRow(icon: "clock", color: .blue, text: "Confirming...", isActive: true)
                signatureDisplay(sig)

            case .confirmed(let sig):
                statusRow(icon: "checkmark.circle.fill", color: .green, text: "Submitted", isActive: false)
                statusRow(icon: "checkmark.circle.fill", color: .green, text: "Confirmed", isActive: false)
                statusRow(icon: "clock", color: .blue, text: "Finalizing...", isActive: true)
                signatureDisplay(sig)

            case .finalized(let sig):
                statusRow(icon: "checkmark.circle.fill", color: .green, text: "Submitted", isActive: false)
                statusRow(icon: "checkmark.circle.fill", color: .green, text: "Confirmed", isActive: false)
                statusRow(icon: "checkmark.circle.fill", color: .green, text: "Finalized", isActive: false)
                signatureDisplay(sig)

            case .failed(let error):
                statusRow(icon: "xmark.circle.fill", color: .red, text: error, isActive: false)
            }
        }
    }

    private func statusRow(icon: String, color: Color, text: String, isActive: Bool) -> some View {
        HStack {
            if isActive {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: icon)
                    .foregroundStyle(color)
            }
            Text(text)
                .font(.body)
            Spacer()
        }
    }

    private func signatureDisplay(_ signature: String) -> some View {
        HStack {
            Text(shortSig(signature))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Button {
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(signature, forType: .string)
                #else
                UIPasteboard.general.string = signature
                #endif
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
    }

    private func shortSig(_ sig: String) -> String {
        guard sig.count > 16 else { return sig }
        return "\(sig.prefix(8))...\(sig.suffix(8))"
    }
}
