import SwiftUI
import DeadboltCore

/// P3-010: NFT selector for send NFT flow.
/// Displays a grid of user's NFTs with image, name, and collection.
struct NFTSelectorView: View {
    let nfts: [NFTAsset]
    let onSelect: (NFTAsset) -> Void
    let isLoading: Bool

    @State private var searchText = ""

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 12)
    ]

    private var filteredNFTs: [NFTAsset] {
        if searchText.isEmpty {
            return nfts
        }
        let query = searchText.lowercased()
        return nfts.filter {
            $0.name.lowercased().contains(query) ||
            $0.symbol.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select NFT")
                .font(.headline)

            TextField("Search NFTs...", text: $searchText)
                .textFieldStyle(.roundedBorder)

            if isLoading {
                VStack {
                    Spacer()
                    ProgressView("Loading NFTs...")
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if filteredNFTs.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text("No NFTs found")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filteredNFTs, id: \.mint.base58) { nft in
                            Button {
                                onSelect(nft)
                            } label: {
                                nftCard(nft)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func nftCard(_ nft: NFTAsset) -> some View {
        VStack(spacing: 4) {
            if let urlStr = nft.imageURL, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        nftPlaceholder
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    @unknown default:
                        nftPlaceholder
                    }
                }
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                nftPlaceholder
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Text(nft.name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .foregroundStyle(.primary)

            if !nft.symbol.isEmpty {
                Text(nft.symbol)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var nftPlaceholder: some View {
        ZStack {
            Color.gray.opacity(0.2)
            Image(systemName: "photo")
                .font(.title)
                .foregroundStyle(.secondary)
        }
    }
}
