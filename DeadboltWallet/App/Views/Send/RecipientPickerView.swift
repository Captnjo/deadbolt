import SwiftUI
import DeadboltCore

/// P8-011: Recipient picker with address book integration.
/// Shows address book entries as suggestions for quick selection.
struct RecipientPickerView: View {
    @Binding var recipientAddress: String
    @Binding var isValid: Bool

    @State private var addressBookEntries: [AddressBookEntry] = []
    @State private var showSuggestions = false

    private var filteredSuggestions: [AddressBookEntry] {
        if recipientAddress.isEmpty {
            return addressBookEntries
        }
        let query = recipientAddress.lowercased()
        return addressBookEntries.filter {
            $0.tag.lowercased().contains(query) ||
            $0.address.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recipient")
                .font(.headline)

            TextField("Enter Solana address or search contacts", text: $recipientAddress)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onChange(of: recipientAddress) { _, newValue in
                    isValid = validateAddress(newValue)
                    showSuggestions = !newValue.isEmpty && !filteredSuggestions.isEmpty && !isValid
                }

            if !recipientAddress.isEmpty && !isValid {
                // Show address book suggestions if we have matches
                if !filteredSuggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredSuggestions, id: \.address) { entry in
                            Button {
                                recipientAddress = entry.address
                                isValid = validateAddress(entry.address)
                                showSuggestions = false
                            } label: {
                                HStack {
                                    Image(systemName: "person.circle")
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.tag)
                                            .fontWeight(.medium)
                                            .foregroundStyle(.primary)
                                        Text(shortAddress(entry.address))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if entry.address != filteredSuggestions.last?.address {
                                Divider()
                            }
                        }
                    }
                    .padding(4)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Text("Invalid Solana address")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            // Quick access: show address book contacts
            if recipientAddress.isEmpty && !addressBookEntries.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Contacts")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(Array(addressBookEntries.prefix(5)), id: \.address) { entry in
                        Button {
                            recipientAddress = entry.address
                            isValid = validateAddress(entry.address)
                        } label: {
                            HStack {
                                Image(systemName: "person.circle")
                                    .foregroundStyle(.secondary)
                                Text(entry.tag)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(shortAddress(entry.address))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(.quaternary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .task {
            await loadAddressBook()
        }
    }

    private func validateAddress(_ address: String) -> Bool {
        guard !address.isEmpty else { return false }
        guard let decoded = try? Base58.decode(address) else { return false }
        return decoded.count == 32
    }

    private func shortAddress(_ address: String) -> String {
        guard address.count > 8 else { return address }
        return "\(address.prefix(4))...\(address.suffix(4))"
    }

    private func loadAddressBook() async {
        let addressBook = AddressBook()
        do {
            try await addressBook.load()
            addressBookEntries = await addressBook.entries()
        } catch {
            // Address book loading failure is non-critical
        }
    }
}
