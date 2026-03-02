import SwiftUI
import DeadboltCore

/// P8-010: Address book view.
/// List entries with tag and address. Add, edit, delete. Search by tag.
struct AddressBookView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [AddressBookEntry] = []
    @State private var searchText = ""
    @State private var showAddSheet = false
    @State private var editingEntry: AddressBookEntry?
    @State private var errorMessage: String?

    private let addressBook = AddressBook()

    private var filteredEntries: [AddressBookEntry] {
        if searchText.isEmpty {
            return entries
        }
        let query = searchText.lowercased()
        return entries.filter {
            $0.tag.lowercased().contains(query) ||
            $0.address.lowercased().contains(query)
        }
    }

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

                Text("Address Book")
                    .font(.headline)

                Spacer()

                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            .padding()

            Divider()

            // Search bar
            TextField("Search by tag...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.vertical, 8)

            // Entries list
            if filteredEntries.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.rectangle.stack")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text(entries.isEmpty ? "No contacts yet" : "No matches found")
                        .foregroundStyle(.secondary)

                    if entries.isEmpty {
                        Button("Add Contact") {
                            showAddSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(filteredEntries, id: \.address) { entry in
                            entryRow(entry)

                            if entry.address != filteredEntries.last?.address {
                                Divider()
                            }
                        }
                    }
                    .padding(.horizontal)
                }
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
            await loadEntries()
        }
        .sheet(isPresented: $showAddSheet) {
            AddAddressSheet(addressBook: addressBook) {
                Task { await loadEntries() }
            }
        }
        .sheet(item: $editingEntry) { entry in
            EditAddressSheet(addressBook: addressBook, entry: entry) {
                Task { await loadEntries() }
            }
        }
    }

    private func entryRow(_ entry: AddressBookEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.tag)
                    .fontWeight(.medium)
                Text(entry.address)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Copy button
            Button {
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.address, forType: .string)
                #else
                UIPasteboard.general.string = entry.address
                #endif
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.plain)

            // Edit button
            Button {
                editingEntry = entry
            } label: {
                Image(systemName: "pencil")
                    .font(.caption)
            }
            .buttonStyle(.plain)

            // Delete button
            Button {
                deleteEntry(entry)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }

    private func loadEntries() async {
        do {
            try await addressBook.load()
            entries = await addressBook.entries()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteEntry(_ entry: AddressBookEntry) {
        Task {
            await addressBook.remove(address: entry.address)
            do {
                try await addressBook.save()
                await loadEntries()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// Make AddressBookEntry Identifiable for sheet binding
extension AddressBookEntry: @retroactive Identifiable {
    public var id: String { address }
}

/// Sheet for adding a new address book entry.
struct AddAddressSheet: View {
    let addressBook: AddressBook
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var tag = ""
    @State private var address = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Address")
                .font(.headline)

            TextField("Tag (e.g. 'Alice')", text: $tag)
                .textFieldStyle(.roundedBorder)

            TextField("Solana address", text: $address)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Save") {
                    saveEntry()
                }
                .buttonStyle(.borderedProminent)
                .disabled(tag.isEmpty || address.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }

    private func saveEntry() {
        Task {
            do {
                try await addressBook.add(address: address, tag: tag)
                try await addressBook.save()
                onSave()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Sheet for editing an existing address book entry.
struct EditAddressSheet: View {
    let addressBook: AddressBook
    let entry: AddressBookEntry
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var tag: String = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Address")
                .font(.headline)

            TextField("Tag", text: $tag)
                .textFieldStyle(.roundedBorder)

            Text(entry.address)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Save") {
                    saveEdit()
                }
                .buttonStyle(.borderedProminent)
                .disabled(tag.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
        .onAppear {
            tag = entry.tag
        }
    }

    private func saveEdit() {
        Task {
            do {
                try await addressBook.update(address: entry.address, tag: tag)
                try await addressBook.save()
                onSave()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
