import 'send.dart' show TxStatus;

class NftAsset {
  final String id;
  final String name;
  final String? imageUrl;
  final String? collection;
  final String mint;

  const NftAsset({
    required this.id,
    required this.name,
    this.imageUrl,
    this.collection,
    required this.mint,
  });

  factory NftAsset.fromDas(Map<String, dynamic> json) {
    final content = json['content'] as Map<String, dynamic>? ?? {};
    final metadata = content['metadata'] as Map<String, dynamic>? ?? {};
    final links = content['links'] as Map<String, dynamic>? ?? {};
    final grouping = json['grouping'] as List<dynamic>? ?? [];

    String? collection;
    for (final g in grouping) {
      if (g is Map<String, dynamic> && g['group_key'] == 'collection') {
        collection = g['group_value'] as String?;
        break;
      }
    }

    return NftAsset(
      id: json['id'] as String,
      name: metadata['name'] as String? ?? 'Unnamed NFT',
      imageUrl: links['image'] as String? ?? content['json_uri'] as String?,
      collection: collection,
      mint: json['id'] as String,
    );
  }
}

enum SendNftStep { selectNft, recipient, review, confirming }

class SendNftState {
  final SendNftStep step;
  final List<NftAsset> nfts;
  final bool isLoadingNfts;
  final String? nftLoadError;
  final NftAsset? selectedNft;
  final String recipient;
  final TxStatus txStatus;
  final String? txSignature;
  final String? confirmationStatus;
  final String? errorMessage;
  final bool simulationSuccess;
  final String? simulationError;

  const SendNftState({
    this.step = SendNftStep.selectNft,
    this.nfts = const [],
    this.isLoadingNfts = false,
    this.nftLoadError,
    this.selectedNft,
    this.recipient = '',
    this.txStatus = TxStatus.idle,
    this.txSignature,
    this.confirmationStatus,
    this.errorMessage,
    this.simulationSuccess = false,
    this.simulationError,
  });

  SendNftState copyWith({
    SendNftStep? step,
    List<NftAsset>? nfts,
    bool? isLoadingNfts,
    String? nftLoadError,
    NftAsset? selectedNft,
    String? recipient,
    TxStatus? txStatus,
    String? txSignature,
    String? confirmationStatus,
    String? errorMessage,
    bool? simulationSuccess,
    String? simulationError,
  }) {
    return SendNftState(
      step: step ?? this.step,
      nfts: nfts ?? this.nfts,
      isLoadingNfts: isLoadingNfts ?? this.isLoadingNfts,
      nftLoadError: nftLoadError ?? this.nftLoadError,
      selectedNft: selectedNft ?? this.selectedNft,
      recipient: recipient ?? this.recipient,
      txStatus: txStatus ?? this.txStatus,
      txSignature: txSignature ?? this.txSignature,
      confirmationStatus: confirmationStatus ?? this.confirmationStatus,
      errorMessage: errorMessage ?? this.errorMessage,
      simulationSuccess: simulationSuccess ?? this.simulationSuccess,
      simulationError: simulationError ?? this.simulationError,
    );
  }
}
