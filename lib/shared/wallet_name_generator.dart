import 'dart:math';

final _rng = Random();

const _adjectives = [
  'Cosmic',
  'Swift',
  'Bold',
  'Neon',
  'Iron',
  'Lunar',
  'Solar',
  'Amber',
  'Frost',
  'Blaze',
  'Coral',
  'Dusk',
  'Ember',
  'Sage',
  'Onyx',
  'Jade',
  'Ruby',
  'Storm',
  'Nova',
  'Pixel',
  'Drift',
  'Echo',
  'Vivid',
  'Lucid',
  'Stark',
  'Prism',
  'Rapid',
  'Quiet',
  'Brisk',
  'Deep',
];

const _nouns = [
  'Falcon',
  'Panda',
  'Tiger',
  'Otter',
  'Raven',
  'Fox',
  'Wolf',
  'Lynx',
  'Hawk',
  'Bear',
  'Viper',
  'Crane',
  'Shark',
  'Eagle',
  'Cobra',
  'Mantis',
  'Bison',
  'Gecko',
  'Heron',
  'Ibex',
  'Manta',
  'Owl',
  'Finch',
  'Stag',
  'Wren',
  'Seal',
  'Frog',
  'Moth',
  'Elk',
  'Ram',
];

String generateWalletName() {
  final adj = _adjectives[_rng.nextInt(_adjectives.length)];
  final noun = _nouns[_rng.nextInt(_nouns.length)];
  return '$adj $noun';
}
