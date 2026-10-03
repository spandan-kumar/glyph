// Builds assets/catalog/catalog.json: the starter items (ids kept stable),
// hand-curated theme variants for every procedural generator, and every
// sprite in a couple of colourways or motions. Validates everything and
// fails loudly on duplicates or bad references.
//
//   dart run tool/build_sprites.dart   # after editing sprite packs
//   dart run tool/build_catalog.dart
import 'dart:convert';
import 'dart:io';

import 'package:glyph/engine/generators/sprite.dart';
import 'package:glyph/engine/palette.dart';
import 'package:glyph/engine/registry.dart';
import 'package:glyph/library/catalog.dart';

/// Bump when adding a batch so "New" sorting surfaces it.
const revision = 2;

/// Revision for the public-domain classics packs (drives the "Just Added" shelf).
const classicsRevision = 3;

const categoryOrder = [
  'Classic Cartoons', 'Storybook', 'Monsters & Legends', 'Masterpieces',
  'Chill', 'Party', 'Emoji', 'Love', 'Holidays', 'Nature', 'Animals', 'Water',
  'Weather', 'Space', 'Fire & Energy', 'Abstract', 'Hypnotic', 'Retro & Digital',
  'Gaming', 'Science & Sims', 'Food & Drink', 'Symbols',
];

/// One curated look: title, palette, params, extra tags (space separated,
/// `_` for a space inside a tag), optional category / speed overrides.
class V {
  const V(this.title, this.palette, this.params, this.tags, {this.cat, this.speed});

  final String title, palette, tags;
  final Map<String, double> params;
  final String? cat;
  final double? speed;
}

typedef Theme = (String category, String tags, List<V> variants);

final themes = <String, Theme>{
  // ---- Original generators: a few extra looks on top of the starter set.
  'plasma': ('Abstract', 'plasma retro smooth', [
    V('Mint Plasma', 'mint', {'speed': 0.3, 'scale': 0.4}, 'fresh green calm', cat: 'Chill'),
    V('Royal Plasma', 'royal', {'speed': 0.35, 'scale': 0.5}, 'purple gold elegant'),
    V('Copper Plasma', 'copper', {'speed': 0.25, 'scale': 0.3}, 'metal warm'),
    V('Cyber Plasma', 'cyberpunk', {'speed': 0.7, 'scale': 0.6}, 'neon pink cyan', cat: 'Retro & Digital'),
  ]),
  'fire': ('Fire & Energy', 'fire flame hot', [
    V('Golden Hearth', 'gold', {'cooling': 0.4, 'sparking': 0.55}, 'cozy fireplace warm', cat: 'Chill'),
    V('Witch Fire', 'halloween', {'cooling': 0.5, 'sparking': 0.7}, 'spooky purple halloween', cat: 'Holidays'),
    V('Ember Bed', 'ember', {'cooling': 0.7, 'sparking': 0.35}, 'embers glow low'),
    V('Arctic Flame', 'arctic', {'cooling': 0.45, 'sparking': 0.65}, 'cold blue ice'),
  ]),
  'rain': ('Retro & Digital', 'code hacker matrix', [
    V('Golden Code', 'gold', {'speed': 0.4, 'density': 0.5}, 'yellow'),
    V('Crimson Code', 'blood', {'speed': 0.6, 'density': 0.6}, 'red alarm'),
    V('Icy Code', 'arctic', {'speed': 0.35, 'density': 0.4}, 'blue cold'),
  ]),
  'metaballs': ('Chill', 'lava lamp blobs retro', [
    V('Mint Lamp', 'mint', {'speed': 0.25, 'count': 4}, 'green fresh'),
    V('Galaxy Lamp', 'galaxy', {'speed': 0.3, 'count': 5}, 'space purple', cat: 'Space'),
    V('Peach Lamp', 'peach', {'speed': 0.2, 'count': 3}, 'soft warm'),
    V('Toxic Ooze', 'toxic', {'speed': 0.45, 'count': 6}, 'green slime', cat: 'Science & Sims'),
  ]),
  'starfield': ('Space', 'stars warp space', [
    V('Golden Warp', 'gold', {'speed': 0.55, 'stars': 40}, 'yellow'),
    V('Crimson Warp', 'blood', {'speed': 0.8, 'stars': 50}, 'red fast'),
    V('Calm Cosmos', 'twilight', {'speed': 0.15, 'stars': 30}, 'slow calm', cat: 'Chill'),
  ]),
  'ripples': ('Water', 'raindrops ripples water', [
    V('Golden Pond', 'gold', {'rate': 0.3, 'speed': 0.35}, 'warm calm', cat: 'Chill'),
    V('Neon Puddles', 'neon', {'rate': 0.6, 'speed': 0.6}, 'night city', cat: 'Party'),
    V('Sakura Pond', 'sakura', {'rate': 0.25, 'speed': 0.3}, 'pink spring japanese', cat: 'Chill'),
  ]),
  'swirl': ('Hypnotic', 'spiral vortex swirl', [
    V('Mint Whirlpool', 'mint', {'speed': 0.3, 'arms': 3, 'twist': 0.7}, 'green water'),
    V('Golden Vortex', 'gold', {'speed': 0.4, 'arms': 4, 'twist': 0.4}, 'yellow'),
    V('Cyber Spiral', 'cyberpunk', {'speed': 0.6, 'arms': 2, 'twist': 0.9}, 'neon', cat: 'Retro & Digital'),
  ]),
  'life': ('Science & Sims', 'cellular automaton conway', [
    V('Golden Life', 'gold', {'speed': 0.35}, 'yellow'),
    V('Ocean Life', 'ocean', {'speed': 0.5}, 'blue'),
    V('Crimson Colony', 'blood', {'speed': 0.6}, 'red'),
  ]),
  'twinkle': ('Chill', 'twinkle sparkle stars', [
    V('Gold Glitter', 'gold', {'density': 0.5, 'fade': 0.5}, 'glitter sparkle', cat: 'Party'),
    V('Snow Glitter', 'arctic', {'density': 0.35, 'fade': 0.6}, 'winter white'),
    V('Fairy Lights', 'pastel', {'density': 0.3, 'fade': 0.7}, 'soft fairy bedroom'),
  ]),
  'aurora': ('Nature', 'aurora sky night', [
    V('Pink Aurora', 'sakura', {'speed': 0.3, 'length': 0.6, 'shimmer': 0.5}, 'pink'),
    V('Golden Aurora', 'gold', {'speed': 0.25, 'length': 0.5, 'shimmer': 0.4}, 'yellow'),
    V('Twilight Aurora', 'twilight', {'speed': 0.2, 'length': 0.7, 'shimmer': 0.3}, 'purple calm', cat: 'Chill'),
  ]),
  'noise': ('Abstract', 'noise flow organic', [
    V('Emerald Flow', 'emerald', {'speed': 0.25, 'scale': 0.5, 'warp': 0.6}, 'green jewel'),
    V('Peach Flow', 'peach', {'speed': 0.2, 'scale': 0.4, 'warp': 0.5}, 'soft warm', cat: 'Chill'),
    V('Copper Flow', 'copper', {'speed': 0.3, 'scale': 0.55, 'warp': 0.8}, 'metal'),
  ]),
  'fireworks': ('Party', 'fireworks celebrate', [
    V('Golden Fireworks', 'gold', {'rate': 0.5, 'size': 0.6, 'trails': 0.6}, 'gold new_year'),
    V('Neon Fireworks', 'neon', {'rate': 0.7, 'size': 0.5, 'trails': 0.5}, 'rave'),
    V('Fourth of July', 'fireice', {'rate': 0.65, 'size': 0.6, 'trails': 0.5}, 'july_4th independence summer', cat: 'Holidays'),
  ]),
  'snow': ('Weather', 'snow winter', [
    V('Sakura Petals', 'sakura', {'amount': 0.3, 'wind': 0.35, 'melt': 0.9}, 'spring pink japanese', cat: 'Nature'),
    V('Golden Leaves', 'autumn', {'amount': 0.35, 'wind': 0.5, 'melt': 0.7}, 'autumn fall', cat: 'Nature'),
    V('Ash Fall', 'mono', {'amount': 0.4, 'wind': -0.2, 'melt': 0.6}, 'grey moody'),
  ]),
  'balls': ('Party', 'bounce balls physics', [
    V('Golden Bounce', 'gold', {'count': 4, 'gravity': 0.4, 'trails': 0.6}, 'yellow'),
    V('Neon Pinball', 'neon', {'count': 6, 'gravity': 0.6, 'trails': 0.4}, 'arcade', cat: 'Gaming'),
  ]),
  'helix': ('Science & Sims', 'dna helix science', [
    V('Golden Helix', 'gold', {'speed': 0.4, 'twist': 0.5, 'rungs': 0.6}, 'yellow'),
    V('Emerald Helix', 'emerald', {'speed': 0.3, 'twist': 0.4, 'rungs': 0.7}, 'green'),
  ]),
  'galaxy': ('Space', 'galaxy spiral space', [
    V('Golden Galaxy', 'gold', {'speed': 0.25, 'arms': 2, 'twist': 0.6}, 'yellow'),
    V('Emerald Galaxy', 'emerald', {'speed': 0.3, 'arms': 3, 'twist': 0.5}, 'green'),
    V('Sapphire Spiral', 'sapphire', {'speed': 0.2, 'arms': 2, 'twist': 0.8}, 'blue'),
  ]),
  'scope': ('Retro & Digital', 'oscilloscope waves signal', [
    V('Golden Signal', 'gold', {'speed': 0.4, 'waves': 2, 'amp': 0.6}, 'yellow'),
    V('Crimson Signal', 'blood', {'speed': 0.6, 'waves': 3, 'amp': 0.7}, 'red'),
  ]),
  'heartbeat': ('Love', 'heart pulse love', [
    V('Racing Heart', 'heart', {'bpm': 140, 'size': 0.6, 'rings': 0.7}, 'excited fast'),
    V('Golden Heart', 'gold', {'bpm': 72, 'size': 0.6, 'rings': 0.5}, 'gold wedding anniversary'),
    V('Neon Heart Pulse', 'neon', {'bpm': 100, 'size': 0.65, 'rings': 0.8}, 'neon party'),
    V('Candy Heart', 'candy', {'bpm': 80, 'size': 0.55, 'rings': 0.5}, 'sweet pink'),
  ]),
  'tunnel': ('Retro & Digital', 'tunnel travel', [
    V('Golden Tunnel', 'gold', {'speed': 0.4, 'segments': 6, 'spin': 0.2}, 'yellow'),
    V('Emerald Tunnel', 'emerald', {'speed': 0.5, 'segments': 4, 'spin': -0.3}, 'green'),
  ]),

  // ---- Library v2 generators.
  'kaleido': ('Hypnotic', 'kaleidoscope mirror symmetry', [
    V('Stained Glass', 'royal', {'speed': 0.25, 'segments': 6, 'zoom': 0.5}, 'jewel glass church'),
    V('Vapor Kaleidoscope', 'vaporwave', {'speed': 0.35, 'segments': 6, 'zoom': 0.5}, 'pastel retro'),
    V('Desert Mandala', 'desert', {'speed': 0.2, 'segments': 8, 'zoom': 0.4}, 'mandala warm', cat: 'Chill'),
    V('Emerald Mandala', 'emerald', {'speed': 0.25, 'segments': 8, 'zoom': 0.6}, 'green mandala'),
    V('Candy Kaleidoscope', 'candy', {'speed': 0.45, 'segments': 5, 'zoom': 0.5}, 'sweet pink'),
    V('Cyber Kaleidoscope', 'cyberpunk', {'speed': 0.6, 'segments': 4, 'zoom': 0.7}, 'neon', cat: 'Party'),
    V('Rainbow Prism', 'rainbow', {'speed': 0.4, 'segments': 6, 'zoom': 0.3}, 'colourful'),
    V('Frost Crystal', 'arctic', {'speed': 0.2, 'segments': 6, 'zoom': 0.45}, 'snowflake winter ice', cat: 'Weather'),
    V('Diwali Mandala', 'diwali', {'speed': 0.3, 'segments': 8, 'zoom': 0.5}, 'diwali rangoli festival', cat: 'Holidays'),
    V('Sapphire Facets', 'sapphire', {'speed': 0.3, 'segments': 3, 'zoom': 0.6}, 'blue jewel'),
  ]),
  'voronoi': ('Abstract', 'cells voronoi mosaic', [
    V('Tropical Mosaic', 'tropical', {'count': 7, 'speed': 0.35, 'edges': 0.6}, 'summer colourful'),
    V('Stained Cells', 'royal', {'count': 9, 'speed': 0.25, 'edges': 0.8}, 'glass'),
    V('Living Tissue', 'blood', {'count': 10, 'speed': 0.2, 'edges': 0.5}, 'biology organic', cat: 'Science & Sims'),
    V('Giraffe Pattern', 'desert', {'count': 8, 'speed': 0.1, 'edges': 0.9}, 'animal print safari', cat: 'Nature'),
    V('Pastel Pebbles', 'pastel', {'count': 6, 'speed': 0.2, 'edges': 0.5}, 'soft calm', cat: 'Chill'),
    V('Neon Shards', 'neon', {'count': 12, 'speed': 0.6, 'edges': 0.7}, 'glass party', cat: 'Party'),
    V('Ice Floes', 'arctic', {'count': 7, 'speed': 0.15, 'edges': 0.9}, 'ice winter', cat: 'Weather'),
    V('Emerald Scales', 'emerald', {'count': 13, 'speed': 0.3, 'edges': 0.6}, 'dragon reptile'),
    V('Autumn Patchwork', 'autumn', {'count': 9, 'speed': 0.2, 'edges': 0.7}, 'quilt fall'),
  ]),
  'interference': ('Water', 'waves interference physics', [
    V('Wave Interference', 'ocean', {'sources': 2, 'speed': 0.45, 'wavelength': 0.45}, 'physics science', cat: 'Science & Sims'),
    V('Moire Pond', 'deepsea', {'sources': 3, 'speed': 0.35, 'wavelength': 0.5}, 'pond calm', cat: 'Chill'),
    V('Neon Ripples', 'neon', {'sources': 2, 'speed': 0.6, 'wavelength': 0.35}, 'party', cat: 'Party'),
    V('Golden Echoes', 'gold', {'sources': 3, 'speed': 0.4, 'wavelength': 0.55}, 'sound'),
    V('Sapphire Sonar', 'sapphire', {'sources': 4, 'speed': 0.5, 'wavelength': 0.4}, 'sonar'),
    V('Candy Waves', 'candy', {'sources': 2, 'speed': 0.3, 'wavelength': 0.6}, 'sweet'),
    V('Toxic Pulse', 'toxic', {'sources': 4, 'speed': 0.7, 'wavelength': 0.3}, 'radioactive', cat: 'Science & Sims'),
    V('Lagoon Shimmer', 'tropical', {'sources': 3, 'speed': 0.3, 'wavelength': 0.65}, 'summer beach'),
  ]),
  'rings': ('Hypnotic', 'rings hypnotic concentric', [
    V('Hypnotic Rings', 'twilight', {'speed': 0.4, 'density': 0.5, 'twist': 0}, 'trance'),
    V('Rainbow Target', 'rainbow', {'speed': 0.5, 'density': 0.6, 'twist': 0}, 'colourful'),
    V('Hypno Spiral', 'mono', {'speed': 0.5, 'density': 0.5, 'twist': 1}, 'black white trance'),
    V('Candy Spiral', 'candy', {'speed': 0.4, 'density': 0.4, 'twist': 2}, 'sweet lollipop'),
    V('Vortex Bloom', 'vaporwave', {'speed': 0.3, 'density': 0.7, 'twist': 3}, 'flower'),
    V('Golden Ripple Rings', 'gold', {'speed': 0.3, 'density': 0.4, 'twist': 0}, 'gold calm', cat: 'Chill'),
    V('Rave Rings', 'cyberpunk', {'speed': 0.9, 'density': 0.6, 'twist': 0}, 'rave fast', cat: 'Party'),
    V('Sapphire Whirl', 'sapphire', {'speed': 0.35, 'density': 0.5, 'twist': 2}, 'blue'),
    V('Holiday Swirl Rings', 'christmas', {'speed': 0.4, 'density': 0.6, 'twist': 1}, 'christmas candy_cane', cat: 'Holidays'),
    V('Infinite Zoom', 'royal', {'speed': 0.6, 'density': 0.8, 'twist': 0}, 'zoom infinite'),
  ]),
  'opart': ('Hypnotic', 'op-art checker optical illusion', [
    V('Op-Art Warp', 'mono', {'speed': 0.4, 'size': 0.5, 'warp': 0.6}, 'black white classic'),
    V('Breathing Checkers', 'mono', {'speed': 0.25, 'size': 0.6, 'warp': 0.9}, 'illusion'),
    V('Candy Checkers', 'candy', {'speed': 0.4, 'size': 0.5, 'warp': 0.6}, 'pink sweet'),
    V('Racing Flag Warp', 'mono', {'speed': 0.8, 'size': 0.3, 'warp': 0.4}, 'race speed', cat: 'Gaming'),
    V('Neon Grid Warp', 'neon', {'speed': 0.5, 'size': 0.4, 'warp': 0.7}, 'neon', cat: 'Retro & Digital'),
    V('Golden Checkers', 'gold', {'speed': 0.3, 'size': 0.6, 'warp': 0.5}, 'gold'),
    V('Christmas Checkers', 'christmas', {'speed': 0.35, 'size': 0.5, 'warp': 0.6}, 'christmas', cat: 'Holidays'),
    V('Jelly Board', 'bubblegum', {'speed': 0.5, 'size': 0.7, 'warp': 1}, 'wobbly'),
  ]),
  'silk': ('Abstract', 'silk liquid flowing', [
    V('Liquid Silk', 'royal', {'speed': 0.35, 'scale': 0.45, 'detail': 4}, 'purple elegant'),
    V('Rose Silk', 'sakura', {'speed': 0.25, 'scale': 0.4, 'detail': 4}, 'pink soft', cat: 'Chill'),
    V('Molten Gold', 'gold', {'speed': 0.3, 'scale': 0.5, 'detail': 3}, 'luxury'),
    V('Ink in Water', 'deepsea', {'speed': 0.2, 'scale': 0.6, 'detail': 5}, 'calm blue', cat: 'Water'),
    V('Oil Slick', 'vaporwave', {'speed': 0.4, 'scale': 0.5, 'detail': 5}, 'iridescent'),
    V('Emerald Silk', 'emerald', {'speed': 0.3, 'scale': 0.4, 'detail': 3}, 'green'),
    V('Lava Silk', 'lava', {'speed': 0.45, 'scale': 0.55, 'detail': 4}, 'hot', cat: 'Fire & Energy'),
    V('Peach Satin', 'peach', {'speed': 0.2, 'scale': 0.35, 'detail': 2}, 'soft warm', cat: 'Chill'),
    V('Galaxy Silk', 'galaxy', {'speed': 0.3, 'scale': 0.6, 'detail': 4}, 'cosmic', cat: 'Space'),
    V('Copper Ribbons', 'copper', {'speed': 0.35, 'scale': 0.3, 'detail': 3}, 'metal'),
  ]),
  'lattice': ('Abstract', 'lattice grid dots pulse', [
    V('Pulse Lattice', 'cyberpunk', {'speed': 0.4, 'scale': 0.5}, 'neon'),
    V('Golden Lattice', 'gold', {'speed': 0.3, 'scale': 0.6}, 'gold'),
    V('Molecule Grid', 'mint', {'speed': 0.35, 'scale': 0.4}, 'chemistry', cat: 'Science & Sims'),
    V('Disco Dots', 'rainbow', {'speed': 0.7, 'scale': 0.5}, 'party dots', cat: 'Party'),
    V('Pastel Polka', 'pastel', {'speed': 0.25, 'scale': 0.6}, 'polka soft', cat: 'Chill'),
    V('Crimson Lattice', 'blood', {'speed': 0.5, 'scale': 0.3}, 'red'),
    V('Ice Lattice', 'arctic', {'speed': 0.3, 'scale': 0.5}, 'crystal winter'),
    V('Synth Lattice', 'synthwave', {'speed': 0.55, 'scale': 0.4}, 'retro', cat: 'Retro & Digital'),
  ]),
  'caustics': ('Water', 'caustics pool underwater light', [
    V('Pool Caustics', 'arctic', {'speed': 0.35, 'scale': 0.5, 'sharp': 0.5}, 'pool summer swimming'),
    V('Tropical Lagoon', 'tropical', {'speed': 0.3, 'scale': 0.45, 'sharp': 0.4}, 'beach summer'),
    V('Deep Reef Light', 'deepsea', {'speed': 0.25, 'scale': 0.6, 'sharp': 0.6}, 'ocean reef', cat: 'Chill'),
    V('Golden Shallows', 'gold', {'speed': 0.3, 'scale': 0.5, 'sharp': 0.5}, 'sunlit'),
    V('Mint Spring', 'mint', {'speed': 0.4, 'scale': 0.4, 'sharp': 0.7}, 'fresh'),
    V('Neon Pool Party', 'neon', {'speed': 0.5, 'scale': 0.5, 'sharp': 0.5}, 'party night', cat: 'Party'),
    V('Moonlit Pool', 'sapphire', {'speed': 0.2, 'scale': 0.55, 'sharp': 0.6}, 'night calm', cat: 'Chill'),
    V('Emerald Cove', 'emerald', {'speed': 0.3, 'scale': 0.5, 'sharp': 0.45}, 'green cove'),
  ]),
  'wash': ('Chill', 'gradient wash ambient', [
    V('Rainbow Wash', 'rainbow', {'speed': 0.3, 'bands': 1, 'spin': 0.2}, 'colourful'),
    V('Sunset Wash', 'sunset', {'speed': 0.15, 'bands': 0.6, 'spin': 0.1}, 'evening warm'),
    V('Ocean Wash', 'ocean', {'speed': 0.2, 'bands': 0.8, 'spin': -0.1}, 'blue'),
    V('Pastel Wash', 'pastel', {'speed': 0.15, 'bands': 0.5, 'spin': 0.05}, 'soft nursery'),
    V('Party Wash', 'festive', {'speed': 0.6, 'bands': 2, 'spin': 0.6}, 'party', cat: 'Party'),
    V('Aurora Wash', 'aurora', {'speed': 0.2, 'bands': 0.7, 'spin': 0.15}, 'northern'),
    V('Vapor Wash', 'vaporwave', {'speed': 0.25, 'bands': 1.2, 'spin': 0.3}, 'retro', cat: 'Retro & Digital'),
    V('Spinning Rainbow', 'rainbow', {'speed': 0.5, 'bands': 2.5, 'spin': 1}, 'spin', cat: 'Party'),
    V('Peach Wash', 'peach', {'speed': 0.15, 'bands': 0.6, 'spin': -0.05}, 'warm'),
    V('Christmas Wash', 'christmas', {'speed': 0.3, 'bands': 1.5, 'spin': 0.2}, 'christmas', cat: 'Holidays'),
  ]),
  'breathe': ('Chill', 'breathe meditation relax ambient', [
    V('Calm Breathing', 'twilight', {'rate': 6, 'depth': 0.7}, 'meditation sleep'),
    V('Box Breathing Blue', 'ocean', {'rate': 4, 'depth': 0.8}, 'focus'),
    V('Sunrise Breath', 'sunset', {'rate': 8, 'depth': 0.6}, 'morning wake'),
    V('Forest Breath', 'forest', {'rate': 6, 'depth': 0.6}, 'nature green'),
    V('Candle Breath', 'ember', {'rate': 5, 'depth': 0.5}, 'warm cozy'),
    V('Night Light', 'sapphire', {'rate': 3, 'depth': 0.4}, 'nursery sleep'),
    V('Heart Breath', 'heart', {'rate': 10, 'depth': 0.7}, 'love', cat: 'Love'),
    V('Mint Breath', 'mint', {'rate': 7, 'depth': 0.6}, 'fresh'),
    V('Pulse Alert', 'blood', {'rate': 30, 'depth': 0.9}, 'alert warning', cat: 'Symbols'),
  ]),
  'bokeh': ('Chill', 'bokeh lights blur', [
    V('Golden Bokeh', 'gold', {'count': 8, 'size': 0.5, 'speed': 0.3}, 'fairy lights'),
    V('City Bokeh', 'cyberpunk', {'count': 10, 'size': 0.4, 'speed': 0.25}, 'city night'),
    V('Christmas Bokeh', 'christmas', {'count': 10, 'size': 0.5, 'speed': 0.2}, 'christmas lights', cat: 'Holidays'),
    V('Pastel Bokeh', 'pastel', {'count': 7, 'size': 0.6, 'speed': 0.2}, 'soft dreamy'),
    V('Underwater Bokeh', 'deepsea', {'count': 9, 'size': 0.5, 'speed': 0.3}, 'bubbles', cat: 'Water'),
    V('Party Bokeh', 'festive', {'count': 14, 'size': 0.4, 'speed': 0.5}, 'party', cat: 'Party'),
    V('Sakura Bokeh', 'sakura', {'count': 8, 'size': 0.5, 'speed': 0.25}, 'pink spring'),
    V('Diwali Bokeh', 'diwali', {'count': 12, 'size': 0.45, 'speed': 0.3}, 'diwali festival lights', cat: 'Holidays'),
    V('Forest Bokeh', 'emerald', {'count': 8, 'size': 0.55, 'speed': 0.2}, 'green nature', cat: 'Nature'),
  ]),
  'retrogrid': ('Retro & Digital', 'synthwave retro 80s outrun grid', [
    V('Retro Horizon', 'synthwave', {'speed': 0.45, 'sun': 0.6}, 'sunset'),
    V('Outrun Drive', 'synthwave', {'speed': 0.8, 'sun': 0.5}, 'fast drive'),
    V('Vapor Horizon', 'vaporwave', {'speed': 0.35, 'sun': 0.7}, 'pastel aesthetic'),
    V('Cyber Highway', 'cyberpunk', {'speed': 0.7, 'sun': 0.4}, 'neon city'),
    V('Golden Hour Grid', 'sunset', {'speed': 0.3, 'sun': 0.8}, 'warm'),
    V('Toxic Grid', 'toxic', {'speed': 0.6, 'sun': 0.5}, 'green hacker'),
    V('Ice Grid', 'arctic', {'speed': 0.4, 'sun': 0.6}, 'cold'),
    V('Halloween Grid', 'halloween', {'speed': 0.5, 'sun': 0.6}, 'halloween spooky', cat: 'Holidays'),
  ]),
  'spinner': ('Symbols', 'loading spinner wait busy', [
    V('Loading Arc', 'neon', {'style': 0, 'speed': 0.5}, 'arc'),
    V('Loading Dots Ring', 'ocean', {'style': 1, 'speed': 0.5}, 'dots'),
    V('Three Dot Bounce', 'candy', {'style': 2, 'speed': 0.5}, 'typing dots'),
    V('Pulse Rings', 'mint', {'style': 3, 'speed': 0.5}, 'pulse'),
    V('Progress Bar', 'toxic', {'style': 4, 'speed': 0.4}, 'progress download'),
    V('Golden Spinner', 'gold', {'style': 0, 'speed': 0.7}, 'gold'),
    V('Rainbow Dots Ring', 'rainbow', {'style': 1, 'speed': 0.7}, 'colourful'),
    V('Sonar Ping', 'sapphire', {'style': 3, 'speed': 0.3}, 'sonar'),
    V('Rainbow Progress', 'rainbow', {'style': 4, 'speed': 0.6}, 'colourful'),
    V('Crimson Spinner', 'blood', {'style': 0, 'speed': 0.9}, 'red busy'),
  ]),
  'radar': ('Retro & Digital', 'radar sonar sweep scan', [
    V('Radar Sweep', 'matrix', {'speed': 0.4, 'blips': 5}, 'green military'),
    V('Sonar Scan', 'deepsea', {'speed': 0.3, 'blips': 4}, 'submarine ocean', cat: 'Water'),
    V('Amber Radar', 'gold', {'speed': 0.4, 'blips': 6}, 'amber vintage'),
    V('Alien Scanner', 'toxic', {'speed': 0.6, 'blips': 8}, 'alien sci-fi', cat: 'Space'),
    V('Crimson Radar', 'blood', {'speed': 0.5, 'blips': 7}, 'alert'),
    V('Ice Radar', 'arctic', {'speed': 0.35, 'blips': 3}, 'cold'),
    V('Weather Radar', 'ocean', {'speed': 0.25, 'blips': 10}, 'weather', cat: 'Weather'),
    V('Cyber Scan', 'cyberpunk', {'speed': 0.7, 'blips': 6}, 'neon hacker'),
  ]),
  'disco': ('Party', 'disco mirror ball dance', [
    V('Disco Ball', 'rainbow', {'speed': 0.4, 'spots': 40}, 'dance club'),
    V('Golden Mirror Ball', 'gold', {'speed': 0.35, 'spots': 45}, 'gold wedding'),
    V('Roller Disco', 'vaporwave', {'speed': 0.6, 'spots': 35}, 'retro 70s'),
    V('Club Lasers', 'cyberpunk', {'speed': 0.8, 'spots': 30}, 'club rave'),
    V('Silver Ball', 'mono', {'speed': 0.3, 'spots': 50}, 'silver classic'),
    V('Festive Ball', 'festive', {'speed': 0.5, 'spots': 40}, 'celebrate'),
    V('Christmas Disco', 'christmas', {'speed': 0.4, 'spots': 40}, 'christmas party', cat: 'Holidays'),
    V('Candy Disco', 'candy', {'speed': 0.5, 'spots': 35}, 'sweet'),
  ]),
  'sky': ('Weather', 'sky day night sun moon', [
    V('Day & Night', 'sunset', {'speed': 0.3, 'start': 0.2, 'stars': 0.6}, 'cycle'),
    V('Golden Sunrise', 'sunset', {'speed': 0.1, 'start': 0.98, 'stars': 0.6}, 'sunrise morning dawn', cat: 'Chill'),
    V('Evening Sunset', 'sunset', {'speed': 0.1, 'start': 0.45, 'stars': 0.6}, 'sunset evening dusk', cat: 'Chill'),
    V('Starry Night Sky', 'twilight', {'speed': 0.05, 'start': 0.72, 'stars': 1}, 'night stars sleep', cat: 'Chill'),
    V('Fast Days', 'sunset', {'speed': 0.9, 'start': 0, 'stars': 0.6}, 'timelapse'),
    V('Pink Dusk', 'sakura', {'speed': 0.15, 'start': 0.48, 'stars': 0.5}, 'pink evening'),
    V('Desert Day', 'desert', {'speed': 0.3, 'start': 0.1, 'stars': 0.7}, 'desert warm'),
    V('Tropical Day', 'tropical', {'speed': 0.25, 'start': 0.15, 'stars': 0.5}, 'summer holiday'),
    V('Autumn Day', 'autumn', {'speed': 0.3, 'start': 0.3, 'stars': 0.4}, 'autumn fall'),
  ]),
  'clouds': ('Weather', 'clouds sky drift', [
    V('Drifting Clouds', 'ocean', {'speed': 0.35, 'cover': 0.5}, 'blue sky calm', cat: 'Chill'),
    V('Sunset Clouds', 'sunset', {'speed': 0.25, 'cover': 0.55}, 'evening'),
    V('Overcast', 'mono', {'speed': 0.3, 'cover': 0.9}, 'grey cloudy'),
    V('Cotton Candy Sky', 'candy', {'speed': 0.2, 'cover': 0.5}, 'pink sweet dreamy', cat: 'Chill'),
    V('Stormy Clouds', 'sapphire', {'speed': 0.8, 'cover': 0.8}, 'storm windy'),
    V('Golden Clouds', 'gold', {'speed': 0.25, 'cover': 0.45}, 'heaven'),
    V('Fair Weather', 'arctic', {'speed': 0.3, 'cover': 0.25}, 'sunny clear'),
    V('Twilight Clouds', 'twilight', {'speed': 0.2, 'cover': 0.6}, 'night purple'),
    V('Peach Clouds', 'peach', {'speed': 0.2, 'cover': 0.5}, 'morning soft'),
  ]),
  'waves': ('Water', 'ocean waves sea surf', [
    V('Ocean Waves', 'ocean', {'speed': 0.4, 'swell': 0.5}, 'beach'),
    V('Calm Sea', 'ocean', {'speed': 0.2, 'swell': 0.2}, 'calm', cat: 'Chill'),
    V('Rough Seas', 'deepsea', {'speed': 0.8, 'swell': 1}, 'storm'),
    V('Tropical Surf', 'tropical', {'speed': 0.5, 'swell': 0.6}, 'summer surfing'),
    V('Sunset Sea', 'sunset', {'speed': 0.3, 'swell': 0.4}, 'evening'),
    V('Arctic Waters', 'arctic', {'speed': 0.3, 'swell': 0.5}, 'cold ice'),
    V('Emerald Sea', 'emerald', {'speed': 0.35, 'swell': 0.5}, 'green'),
    V('Lava Sea', 'lava', {'speed': 0.3, 'swell': 0.6}, 'hot alien', cat: 'Fire & Energy'),
    V('Moonlit Waves', 'sapphire', {'speed': 0.25, 'swell': 0.3}, 'night', cat: 'Chill'),
  ]),
  'windowrain': ('Weather', 'rain window cozy city', [
    V('Rainy Window', 'cyberpunk', {'rain': 0.5, 'lights': 0.6}, 'city night'),
    V('Cozy Rainy Night', 'ember', {'rain': 0.4, 'lights': 0.7}, 'cozy warm', cat: 'Chill'),
    V('Monsoon Window', 'ocean', {'rain': 0.9, 'lights': 0.5}, 'monsoon heavy'),
    V('Christmas Window', 'christmas', {'rain': 0.3, 'lights': 0.8}, 'christmas lights', cat: 'Holidays'),
    V('Neon Downpour', 'neon', {'rain': 0.8, 'lights': 0.7}, 'neon'),
    V('Golden City Rain', 'gold', {'rain': 0.5, 'lights': 0.6}, 'city'),
    V('Drizzle', 'sapphire', {'rain': 0.2, 'lights': 0.5}, 'light rain calm', cat: 'Chill'),
    V('Sakura Rain', 'sakura', {'rain': 0.4, 'lights': 0.6}, 'pink spring'),
  ]),
  'lightning': ('Weather', 'storm lightning thunder', [
    V('Thunderstorm', 'arctic', {'rate': 0.5, 'rain': 0.6}, 'storm'),
    V('Electric Storm', 'neon', {'rate': 0.8, 'rain': 0.4}, 'electric', cat: 'Fire & Energy'),
    V('Distant Storm', 'sapphire', {'rate': 0.25, 'rain': 0.3}, 'calm distant', cat: 'Chill'),
    V('Purple Lightning', 'twilight', {'rate': 0.6, 'rain': 0.7}, 'purple'),
    V('Haunted Storm', 'halloween', {'rate': 0.5, 'rain': 0.5}, 'halloween spooky', cat: 'Holidays'),
    V('Dry Lightning', 'gold', {'rate': 0.7, 'rain': 0}, 'desert'),
    V('Tropical Storm', 'tropical', {'rate': 0.4, 'rain': 1}, 'monsoon'),
    V('Crimson Storm', 'blood', {'rate': 0.6, 'rain': 0.5}, 'red'),
  ]),
  'meteors': ('Space', 'meteor shooting stars night', [
    V('Meteor Shower', 'galaxy', {'rate': 0.5, 'speed': 0.5, 'tail': 0.6}, 'perseids'),
    V('Wishing Stars', 'twilight', {'rate': 0.25, 'speed': 0.4, 'tail': 0.7}, 'wish calm', cat: 'Chill'),
    V('Fireball Storm', 'ember', {'rate': 0.8, 'speed': 0.7, 'tail': 0.6}, 'fire', cat: 'Fire & Energy'),
    V('Ice Comets', 'arctic', {'rate': 0.5, 'speed': 0.6, 'tail': 0.8}, 'ice'),
    V('Golden Meteors', 'gold', {'rate': 0.4, 'speed': 0.5, 'tail': 0.6}, 'gold'),
    V('Neon Streaks', 'neon', {'rate': 0.7, 'speed': 0.8, 'tail': 0.5}, 'neon', cat: 'Party'),
    V('Emerald Meteors', 'emerald', {'rate': 0.45, 'speed': 0.5, 'tail': 0.7}, 'green'),
    V('Starfall', 'mono', {'rate': 0.6, 'speed': 0.4, 'tail': 0.8}, 'white'),
    V('New Year Meteors', 'festive', {'rate': 0.7, 'speed': 0.6, 'tail': 0.6}, 'new_year celebrate', cat: 'Holidays'),
  ]),
  'orbits': ('Space', 'planets orbit solar system', [
    V('Solar System', 'galaxy', {'planets': 4, 'speed': 0.4, 'tilt': 0.55}, 'astronomy'),
    V('Top-Down Orbits', 'galaxy', {'planets': 5, 'speed': 0.35, 'tilt': 0}, 'orrery'),
    V('Binary Worlds', 'fireice', {'planets': 2, 'speed': 0.5, 'tilt': 0.6}, 'two'),
    V('Golden Orrery', 'gold', {'planets': 5, 'speed': 0.3, 'tilt': 0.4}, 'clockwork steampunk'),
    V('Pastel Planets', 'pastel', {'planets': 4, 'speed': 0.3, 'tilt': 0.5}, 'soft kids', cat: 'Chill'),
    V('Neon Orbits', 'neon', {'planets': 3, 'speed': 0.7, 'tilt': 0.7}, 'neon'),
    V('Lonely Moon', 'mono', {'planets': 1, 'speed': 0.3, 'tilt': 0.6}, 'moon calm'),
    V('Atom Model', 'toxic', {'planets': 3, 'speed': 0.9, 'tilt': 0.9}, 'atom science physics', cat: 'Science & Sims'),
  ]),
  'blackhole': ('Space', 'black hole gravity accretion', [
    V('Black Hole', 'ember', {'speed': 0.45, 'tilt': 0.6, 'size': 0.5}, 'event horizon'),
    V('Blue Singularity', 'arctic', {'speed': 0.5, 'tilt': 0.5, 'size': 0.4}, 'blue'),
    V('Face-On Accretion', 'lava', {'speed': 0.4, 'tilt': 0, 'size': 0.5}, 'disc'),
    V('Golden Ring', 'gold', {'speed': 0.35, 'tilt': 0.7, 'size': 0.6}, 'ring'),
    V('Violet Void', 'twilight', {'speed': 0.5, 'tilt': 0.65, 'size': 0.55}, 'purple'),
    V('Quasar Core', 'neon', {'speed': 0.8, 'tilt': 0.5, 'size': 0.3}, 'quasar'),
    V('Gargantuan', 'copper', {'speed': 0.3, 'tilt': 0.8, 'size': 0.7}, 'huge'),
    V('Emerald Void', 'emerald', {'speed': 0.45, 'tilt': 0.6, 'size': 0.45}, 'green'),
  ]),
  'borealis': ('Nature', 'northern lights aurora borealis night', [
    V('Borealis Over Pines', 'aurora', {'speed': 0.35, 'activity': 0.55}, 'forest night'),
    V('Quiet Borealis', 'aurora', {'speed': 0.15, 'activity': 0.3}, 'calm', cat: 'Chill'),
    V('Solar Storm Lights', 'aurora', {'speed': 0.6, 'activity': 1}, 'storm active'),
    V('Pink Borealis', 'sakura', {'speed': 0.3, 'activity': 0.6}, 'pink'),
    V('Arctic Borealis', 'arctic', {'speed': 0.3, 'activity': 0.5}, 'blue'),
    V('Emerald Borealis', 'emerald', {'speed': 0.3, 'activity': 0.6}, 'green'),
    V('Violet Borealis', 'twilight', {'speed': 0.25, 'activity': 0.5}, 'purple'),
    V('Christmas Eve Lights', 'christmas', {'speed': 0.3, 'activity': 0.5}, 'christmas', cat: 'Holidays'),
  ]),
  'fireflies': ('Nature', 'fireflies night summer glow', [
    V('Firefly Meadow', 'forest', {'count': 10, 'speed': 0.4}, 'meadow summer', cat: 'Chill'),
    V('Firefly Swarm', 'forest', {'count': 22, 'speed': 0.6}, 'swarm'),
    V('Golden Fireflies', 'gold', {'count': 12, 'speed': 0.35}, 'gold'),
    V('Blue Glowworms', 'arctic', {'count': 14, 'speed': 0.25}, 'cave glowworm'),
    V('Fairy Garden', 'candy', {'count': 10, 'speed': 0.4}, 'fairy magic'),
    V('Swamp Lights', 'toxic', {'count': 8, 'speed': 0.3}, 'swamp spooky', cat: 'Holidays'),
    V('Lantern Festival', 'ember', {'count': 16, 'speed': 0.2}, 'lanterns festival'),
    V('Sleepy Fireflies', 'emerald', {'count': 6, 'speed': 0.15}, 'sleep calm', cat: 'Chill'),
  ]),
  'candle': ('Chill', 'candle flame cozy', [
    V('Candlelight', 'ember', {'count': 1, 'flicker': 0.5}, 'romantic'),
    V('Three Candles', 'ember', {'count': 3, 'flicker': 0.5}, 'trio'),
    V('Drafty Candle', 'lava', {'count': 1, 'flicker': 1}, 'windy'),
    V('Still Flame', 'gold', {'count': 1, 'flicker': 0.1}, 'meditation calm'),
    V('Romantic Candles', 'heart', {'count': 2, 'flicker': 0.4}, 'romantic date', cat: 'Love'),
    V('Spooky Candles', 'halloween', {'count': 3, 'flicker': 0.7}, 'halloween', cat: 'Holidays'),
    V('Advent Candles', 'christmas', {'count': 3, 'flicker': 0.4}, 'christmas advent', cat: 'Holidays'),
    V('Spirit Flame', 'arctic', {'count': 1, 'flicker': 0.6}, 'blue ghost'),
    V('Diwali Candles', 'diwali', {'count': 3, 'flicker': 0.5}, 'diwali festival', cat: 'Holidays'),
  ]),
  'magma': ('Fire & Energy', 'magma lava volcanic', [
    V('Lava Field', 'lava', {'speed': 0.35, 'crust': 0.5}, 'volcano'),
    V('Molten Core', 'ember', {'speed': 0.5, 'crust': 0.3}, 'core hot'),
    V('Cooling Crust', 'lava', {'speed': 0.15, 'crust': 0.85}, 'slow'),
    V('Blue Magma', 'arctic', {'speed': 0.35, 'crust': 0.5}, 'alien'),
    V('Toxic Sludge', 'toxic', {'speed': 0.3, 'crust': 0.6}, 'toxic', cat: 'Science & Sims'),
    V('Golden Veins', 'gold', {'speed': 0.25, 'crust': 0.6}, 'gold marble'),
    V('Plasma Cracks', 'neon', {'speed': 0.45, 'crust': 0.4}, 'neon'),
    V('Hellfire Ground', 'blood', {'speed': 0.4, 'crust': 0.5}, 'halloween', cat: 'Holidays'),
    V('Kintsugi', 'copper', {'speed': 0.1, 'crust': 0.7}, 'japanese gold cracks', cat: 'Abstract'),
  ]),
  'reaction': ('Science & Sims', 'reaction diffusion turing pattern organic', [
    V('Coral Growth', 'mint', {'speed': 0.5, 'pattern': 0}, 'coral'),
    V('Worm Trails', 'ember', {'speed': 0.5, 'pattern': 1}, 'worms'),
    V('Labyrinth Skin', 'emerald', {'speed': 0.5, 'pattern': 2}, 'maze skin'),
    V('Morphing Membrane', 'twilight', {'speed': 0.5, 'pattern': 3}, 'morph'),
    V('Zebra Stripes', 'mono', {'speed': 0.4, 'pattern': 2}, 'zebra animal', cat: 'Nature'),
    V('Leopard Spots', 'desert', {'speed': 0.4, 'pattern': 0}, 'leopard animal', cat: 'Nature'),
    V('Neon Organism', 'neon', {'speed': 0.7, 'pattern': 3}, 'neon'),
    V('Coral Reef', 'tropical', {'speed': 0.5, 'pattern': 0}, 'reef ocean', cat: 'Water'),
    V('Fingerprint', 'copper', {'speed': 0.3, 'pattern': 2}, 'fingerprint'),
  ]),
  'ant': ('Science & Sims', 'langton ant automaton emergent', [
    V("Langton's Ant", 'cmy', {'speed': 0.5, 'ants': 1, 'rule': 0}, 'classic'),
    V('Ant Colony', 'cmy', {'speed': 0.6, 'ants': 4, 'rule': 0}, 'colony'),
    V('Triangle Turmite', 'rainbow', {'speed': 0.6, 'ants': 2, 'rule': 1}, 'turmite'),
    V('Square Builder', 'candy', {'speed': 0.5, 'ants': 1, 'rule': 2}, 'square'),
    V('Spiral Turmite', 'vaporwave', {'speed': 0.7, 'ants': 1, 'rule': 3}, 'spiral'),
    V('Neon Ants', 'neon', {'speed': 0.8, 'ants': 3, 'rule': 0}, 'neon'),
    V('Golden Turmites', 'gold', {'speed': 0.5, 'ants': 2, 'rule': 2}, 'gold'),
    V('Toxic Crawl', 'toxic', {'speed': 0.6, 'ants': 3, 'rule': 1}, 'green'),
  ]),
  'maze': ('Science & Sims', 'maze labyrinth solver puzzle', [
    V('Maze Runner', 'neon', {'speed': 0.5}, 'solve'),
    V('Slow Maze', 'ocean', {'speed': 0.15}, 'slow calm', cat: 'Chill'),
    V('Speed Maze', 'rainbow', {'speed': 1}, 'fast'),
    V('Golden Labyrinth', 'gold', {'speed': 0.4}, 'gold'),
    V('Hedge Maze', 'forest', {'speed': 0.4}, 'garden hedge', cat: 'Nature'),
    V('Haunted Maze', 'halloween', {'speed': 0.5}, 'halloween', cat: 'Holidays'),
    V('Cyber Maze', 'cyberpunk', {'speed': 0.7}, 'cyber', cat: 'Retro & Digital'),
    V('Arcade Maze', 'synthwave', {'speed': 0.6}, 'arcade', cat: 'Gaming'),
  ]),
  'sand': ('Science & Sims', 'falling sand pixel physics', [
    V('Falling Sand', 'desert', {'rate': 0.5, 'spouts': 2}, 'sand'),
    V('Rainbow Sand', 'rainbow', {'rate': 0.6, 'spouts': 3}, 'colourful'),
    V('Hourglass Sand', 'gold', {'rate': 0.3, 'spouts': 1}, 'hourglass time', cat: 'Chill'),
    V('Candy Sprinkles', 'candy', {'rate': 0.7, 'spouts': 3}, 'sprinkles sweet', cat: 'Food & Drink'),
    V('Snow Pile', 'arctic', {'rate': 0.5, 'spouts': 2}, 'snow winter', cat: 'Weather'),
    V('Sand Art', 'sunset', {'rate': 0.5, 'spouts': 2}, 'art layers'),
    V('Neon Particles', 'neon', {'rate': 0.8, 'spouts': 3}, 'neon'),
    V('Beach Sand', 'tropical', {'rate': 0.4, 'spouts': 1}, 'beach summer'),
    V('Christmas Sprinkles', 'christmas', {'rate': 0.6, 'spouts': 3}, 'christmas', cat: 'Holidays'),
  ]),
  'pixelsort': ('Retro & Digital', 'pixel sort glitch art sorting', [
    V('Pixel Sort', 'vaporwave', {'speed': 0.5, 'direction': 0}, 'glitch art'),
    V('Sideways Sort', 'synthwave', {'speed': 0.5, 'direction': 1}, 'horizontal'),
    V('Sorting Algorithm', 'rainbow', {'speed': 0.8, 'direction': 0}, 'algorithm computer', cat: 'Science & Sims'),
    V('Sunset Sort', 'sunset', {'speed': 0.4, 'direction': 0}, 'sunset'),
    V('Ocean Sort', 'ocean', {'speed': 0.4, 'direction': 1}, 'blue'),
    V('Cyber Sort', 'cyberpunk', {'speed': 0.7, 'direction': 1}, 'cyber'),
    V('Golden Sort', 'gold', {'speed': 0.35, 'direction': 0}, 'gold'),
    V('Data Melt', 'toxic', {'speed': 0.6, 'direction': 0}, 'melt hacker'),
  ]),
  'glitch': ('Retro & Digital', 'glitch signal broken vhs', [
    V('Signal Glitch', 'cyberpunk', {'intensity': 0.5, 'speed': 0.5}, 'cyber'),
    V('VHS Tracking', 'vaporwave', {'intensity': 0.4, 'speed': 0.3}, 'vhs 80s'),
    V('System Failure', 'blood', {'intensity': 0.9, 'speed': 0.7}, 'error alert'),
    V('Hacker Glitch', 'matrix', {'intensity': 0.6, 'speed': 0.6}, 'hacker'),
    V('Glitch Rainbow', 'rainbow', {'intensity': 0.5, 'speed': 0.6}, 'colourful'),
    V('Broadcast Interference', 'mono', {'intensity': 0.7, 'speed': 0.4}, 'tv static'),
    V('Haunted Signal', 'halloween', {'intensity': 0.6, 'speed': 0.5}, 'halloween', cat: 'Holidays'),
    V('Synth Glitch', 'synthwave', {'intensity': 0.4, 'speed': 0.7}, 'synth'),
  ]),
  'confetti': ('Party', 'confetti celebrate party', [
    V('Confetti Shower', 'festive', {'amount': 0.5, 'wind': 0, 'bursts': 0.4}, 'celebrate'),
    V('Birthday Confetti', 'candy', {'amount': 0.6, 'wind': 0.1, 'bursts': 0.6}, 'birthday'),
    V('Golden Confetti', 'gold', {'amount': 0.5, 'wind': -0.2, 'bursts': 0.5}, 'gold new_year', cat: 'Holidays'),
    V('Rainbow Confetti', 'rainbow', {'amount': 0.7, 'wind': 0.3, 'bursts': 0.3}, 'rainbow pride'),
    V('Confetti Cannons', 'festive', {'amount': 0.3, 'wind': 0, 'bursts': 1}, 'cannon burst'),
    V('Christmas Confetti', 'christmas', {'amount': 0.5, 'wind': 0.2, 'bursts': 0.3}, 'christmas', cat: 'Holidays'),
    V('Wedding Petals', 'sakura', {'amount': 0.4, 'wind': 0.3, 'bursts': 0}, 'wedding petals', cat: 'Love'),
    V('Halloween Confetti', 'halloween', {'amount': 0.5, 'wind': -0.3, 'bursts': 0.4}, 'halloween', cat: 'Holidays'),
    V('Windy Confetti', 'tropical', {'amount': 0.6, 'wind': 0.9, 'bursts': 0}, 'windy summer'),
    V('Diwali Confetti', 'diwali', {'amount': 0.6, 'wind': 0.1, 'bursts': 0.6}, 'diwali festival', cat: 'Holidays'),
  ]),
  'bubbles': ('Water', 'bubbles underwater aquarium', [
    V('Rising Bubbles', 'deepsea', {'count': 8, 'size': 0.5}, 'aquarium'),
    V('Fizzy Drink', 'gold', {'count': 16, 'size': 0.2}, 'fizzy champagne soda', cat: 'Food & Drink'),
    V('Big Bubbles', 'arctic', {'count': 5, 'size': 1}, 'big calm', cat: 'Chill'),
    V('Bubble Bath', 'candy', {'count': 10, 'size': 0.6}, 'bath kids'),
    V('Lava Bubbles', 'lava', {'count': 8, 'size': 0.5}, 'hot', cat: 'Fire & Energy'),
    V('Potion Bubbles', 'toxic', {'count': 12, 'size': 0.4}, 'potion witch', cat: 'Holidays'),
    V('Tropical Bubbles', 'tropical', {'count': 9, 'size': 0.5}, 'summer'),
    V('Neon Bubbles', 'neon', {'count': 12, 'size': 0.4}, 'neon party', cat: 'Party'),
  ]),
  'equalizer': ('Party', 'equalizer music bars dj', [
    V('Equalizer', 'rainbow', {'bpm': 120, 'energy': 0.6, 'style': 0}, 'music'),
    V('Bass Bars', 'neon', {'bpm': 128, 'energy': 0.9, 'style': 0}, 'bass edm'),
    V('Mirror Meter', 'cyberpunk', {'bpm': 120, 'energy': 0.7, 'style': 1}, 'mirror'),
    V('Chill Beats', 'twilight', {'bpm': 80, 'energy': 0.4, 'style': 0}, 'lofi chill', cat: 'Chill'),
    V('Rainbow Columns', 'rainbow', {'bpm': 110, 'energy': 0.6, 'style': 2}, 'columns'),
    V('Classic VU', 'toxic', {'bpm': 100, 'energy': 0.5, 'style': 0}, 'vu meter retro', cat: 'Retro & Digital'),
    V('Drum & Bass', 'fireice', {'bpm': 174, 'energy': 1, 'style': 1}, 'dnb fast'),
    V('Golden Groove', 'gold', {'bpm': 96, 'energy': 0.6, 'style': 0}, 'funk'),
    V('Synth Pop Bars', 'synthwave', {'bpm': 118, 'energy': 0.7, 'style': 2}, 'synth pop'),
  ]),
  'pendulum': ('Science & Sims', 'pendulum wave physics harmonic', [
    V('Pendulum Wave', 'rainbow', {'speed': 0.45, 'trails': 0.5}, 'physics'),
    V('Slow Pendulums', 'ocean', {'speed': 0.15, 'trails': 0.7}, 'calm', cat: 'Chill'),
    V('Golden Pendulums', 'gold', {'speed': 0.4, 'trails': 0.5}, 'gold'),
    V('Neon Swing', 'neon', {'speed': 0.7, 'trails': 0.3}, 'neon', cat: 'Party'),
    V('Candy Swing', 'candy', {'speed': 0.5, 'trails': 0.6}, 'sweet'),
    V('Cyber Pendulums', 'cyberpunk', {'speed': 0.6, 'trails': 0.4}, 'cyber'),
    V('Aurora Swing', 'aurora', {'speed': 0.3, 'trails': 0.8}, 'aurora'),
    V('Sunset Swing', 'sunset', {'speed': 0.35, 'trails': 0.6}, 'sunset'),
  ]),
  'boids': ('Nature', 'flock birds murmuration swarm', [
    V('Starling Murmuration', 'sunset', {'count': 20, 'trails': 0.5}, 'starlings evening'),
    V('Fish School', 'ocean', {'count': 18, 'trails': 0.4}, 'fish ocean', cat: 'Water'),
    V('Bat Swarm', 'halloween', {'count': 16, 'trails': 0.3}, 'bats halloween', cat: 'Holidays'),
    V('Drone Swarm', 'cyberpunk', {'count': 12, 'trails': 0.6}, 'drones tech', cat: 'Retro & Digital'),
    V('Golden Flock', 'gold', {'count': 14, 'trails': 0.5}, 'gold'),
    V('Firefly Flock', 'forest', {'count': 24, 'trails': 0.7}, 'fireflies'),
    V('Butterfly Swarm', 'candy', {'count': 10, 'trails': 0.4}, 'butterflies spring'),
    V('Arctic Terns', 'arctic', {'count': 16, 'trails': 0.5}, 'birds winter'),
  ]),
  'flowfield': ('Abstract', 'flow field particles trails generative', [
    V('Flow Field', 'aurora', {'count': 45, 'speed': 0.45, 'trails': 0.7}, 'generative'),
    V('Wind Map', 'ocean', {'count': 60, 'speed': 0.5, 'trails': 0.8}, 'wind weather', cat: 'Weather'),
    V('Ember Drift', 'ember', {'count': 40, 'speed': 0.35, 'trails': 0.7}, 'embers', cat: 'Fire & Energy'),
    V('Neon Currents', 'neon', {'count': 70, 'speed': 0.6, 'trails': 0.6}, 'neon'),
    V('Silk Threads', 'royal', {'count': 30, 'speed': 0.3, 'trails': 0.9}, 'threads elegant'),
    V('Pollen Breeze', 'spring', {'count': 50, 'speed': 0.3, 'trails': 0.6}, 'spring pollen', cat: 'Nature'),
    V('Golden Streams', 'gold', {'count': 45, 'speed': 0.4, 'trails': 0.8}, 'gold'),
    V('Data Streams', 'matrix', {'count': 90, 'speed': 0.7, 'trails': 0.5}, 'data hacker', cat: 'Retro & Digital'),
    V('Pastel Breeze', 'pastel', {'count': 40, 'speed': 0.25, 'trails': 0.8}, 'soft calm', cat: 'Chill'),
  ]),
  'floaters': ('Love', 'floating shapes', [
    V('Rising Hearts', 'heart', {'shape': 0, 'count': 6, 'direction': 1}, 'hearts valentine love'),
    V('Raining Hearts', 'candy', {'shape': 0, 'count': 8, 'direction': -1}, 'hearts valentine'),
    V('Floating Stars', 'gold', {'shape': 1, 'count': 7, 'direction': 1}, 'stars wish', cat: 'Chill'),
    V('Falling Stars', 'twilight', {'shape': 1, 'count': 6, 'direction': -0.6}, 'stars night', cat: 'Space'),
    V('Cherry Blossom Fall', 'sakura', {'shape': 2, 'count': 8, 'direction': -0.6}, 'sakura spring petals', cat: 'Nature'),
    V('Autumn Petals', 'autumn', {'shape': 2, 'count': 7, 'direction': -0.8}, 'autumn leaves', cat: 'Nature'),
    V('Big Snowflakes', 'ice', {'shape': 3, 'count': 6, 'direction': -0.5}, 'snow winter christmas', cat: 'Weather'),
    V('Christmas Flakes', 'christmas', {'shape': 3, 'count': 7, 'direction': -0.6}, 'christmas snow', cat: 'Holidays'),
    V('Floating Notes', 'neon', {'shape': 4, 'count': 6, 'direction': 1}, 'music notes', cat: 'Party'),
    V('Valentine Hearts', 'heart', {'shape': 0, 'count': 12, 'direction': 0.7}, 'valentine romance', cat: 'Holidays'),
    V('Golden Notes', 'gold', {'shape': 4, 'count': 5, 'direction': 0.5}, 'music'),
    V('Hovering Hearts', 'bubblegum', {'shape': 0, 'count': 5, 'direction': 0}, 'hearts calm'),
  ]),
  'comets': ('Space', 'comets trails orbit', [
    V('Comet Chase', 'fireice', {'count': 3, 'speed': 0.5, 'tail': 0.7}, 'chase'),
    V('Lone Comet', 'arctic', {'count': 1, 'speed': 0.4, 'tail': 0.9}, 'calm', cat: 'Chill'),
    V('Comet Swarm', 'rainbow', {'count': 6, 'speed': 0.6, 'tail': 0.6}, 'colourful', cat: 'Party'),
    V('Golden Comets', 'gold', {'count': 3, 'speed': 0.5, 'tail': 0.8}, 'gold'),
    V('Neon Comets', 'neon', {'count': 4, 'speed': 0.7, 'tail': 0.5}, 'neon'),
    V('Firefly Comets', 'forest', {'count': 5, 'speed': 0.3, 'tail': 0.6}, 'green'),
    V('Heart Comets', 'heart', {'count': 2, 'speed': 0.4, 'tail': 0.8}, 'love pair', cat: 'Love'),
    V('Ember Comets', 'ember', {'count': 3, 'speed': 0.6, 'tail': 0.7}, 'fire', cat: 'Fire & Energy'),
  ]),
  'spiro': ('Abstract', 'spirograph geometry drawing', [
    V('Spirograph', 'candy', {'speed': 0.45, 'trail': 0.8}, 'drawing'),
    V('Neon Spirograph', 'neon', {'speed': 0.6, 'trail': 0.7}, 'neon'),
    V('Golden Geometry', 'gold', {'speed': 0.4, 'trail': 0.9}, 'sacred geometry'),
    V('Rainbow Rosette', 'rainbow', {'speed': 0.5, 'trail': 0.85}, 'rosette'),
    V('Ocean Spiro', 'ocean', {'speed': 0.35, 'trail': 0.9}, 'calm', cat: 'Chill'),
    V('Cyber Spiro', 'cyberpunk', {'speed': 0.7, 'trail': 0.6}, 'cyber'),
    V('Royal Rosette', 'royal', {'speed': 0.4, 'trail': 0.8}, 'royal'),
    V('Christmas Ornament', 'christmas', {'speed': 0.45, 'trail': 0.85}, 'christmas', cat: 'Holidays'),
  ]),
  'wireframe': ('Retro & Digital', 'wireframe 3d vector geometry', [
    V('Spinning Cube', 'cyberpunk', {'shape': 0, 'speed': 0.45, 'size': 0.7}, 'cube'),
    V('Octahedron', 'neon', {'shape': 1, 'speed': 0.45, 'size': 0.7}, 'octahedron'),
    V('Tetrahedron', 'toxic', {'shape': 2, 'speed': 0.5, 'size': 0.75}, 'tetrahedron'),
    V('Pyramid', 'gold', {'shape': 3, 'speed': 0.35, 'size': 0.7}, 'pyramid egypt'),
    V('Vector Cube', 'matrix', {'shape': 0, 'speed': 0.6, 'size': 0.6}, 'vector 80s'),
    V('Crystal Octahedron', 'arctic', {'shape': 1, 'speed': 0.3, 'size': 0.8}, 'crystal', cat: 'Chill'),
    V('Rainbow Cube', 'rainbow', {'shape': 0, 'speed': 0.5, 'size': 0.75}, 'colourful'),
    V('Synth Pyramid', 'synthwave', {'shape': 3, 'speed': 0.5, 'size': 0.8}, 'synth'),
    V('Ruby Tetra', 'blood', {'shape': 2, 'speed': 0.4, 'size': 0.7}, 'ruby'),
  ]),
};

/// Featured shelf, in order. Must all exist.
const featuredIds = [
  'ocean-plasma', 'beating-heart', 'retro-horizon', 'smiley', 'northern-lights', 'twinkling-christmas-tree',
  'jack-o-lantern', 'stained-glass', 'falling-sand', 'pool-caustics', 'disco-ball', 'little-fish',
  'rainy-window', 'maze-runner', 'equalizer', 'black-hole', 'coral-growth', 'spinning-earth',
  'campfire', 'fireflies', 'hypnotic-rings', 'thunderstorm', 'liquid-silk', 'happy-birthday-banner',
];

const paletteWords = <String, String>{
  'rainbow': 'rainbow colourful', 'sunset': 'orange pink warm', 'ocean': 'blue teal', 'lava': 'red orange hot',
  'forest': 'green', 'neon': 'neon pink cyan', 'ice': 'blue white cold', 'matrix': 'green',
  'aurora': 'green teal purple', 'synthwave': 'purple pink retro', 'christmas': 'red green christmas',
  'festive': 'orange pink purple', 'galaxy': 'purple blue', 'heart': 'red pink', 'pastel': 'pastel soft',
  'halloween': 'purple orange halloween', 'candy': 'pink blue sweet', 'ember': 'orange red warm',
  'gold': 'gold yellow', 'mint': 'mint green', 'cyberpunk': 'pink cyan neon', 'toxic': 'green lime',
  'twilight': 'purple violet', 'sakura': 'pink', 'autumn': 'orange brown autumn', 'tropical': 'teal yellow coral',
  'deepsea': 'blue teal dark', 'desert': 'brown tan warm', 'royal': 'purple gold', 'arctic': 'blue white cold',
  'bubblegum': 'pink blue', 'fireice': 'blue orange', 'mono': 'white grey', 'blood': 'red',
  'spring': 'pastel green pink spring', 'diwali': 'orange magenta gold', 'emerald': 'green', 'sapphire': 'blue',
  'vaporwave': 'pink cyan pastel', 'peach': 'peach orange soft', 'cmy': 'cyan magenta yellow', 'copper': 'copper bronze',
};

const paletteAdjective = <String, String>{
  'neon': 'Neon', 'gold': 'Golden', 'candy': 'Candy', 'galaxy': 'Cosmic', 'ocean': 'Ocean', 'ice': 'Icy',
  'lava': 'Molten', 'toxic': 'Toxic', 'cyberpunk': 'Cyber', 'pastel': 'Pastel', 'rainbow': 'Rainbow',
  'vaporwave': 'Vapor', 'sakura': 'Sakura', 'royal': 'Royal', 'emerald': 'Emerald', 'sapphire': 'Sapphire',
  'mint': 'Minty', 'blood': 'Crimson', 'twilight': 'Twilight', 'festive': 'Festive', 'arctic': 'Arctic',
  'sunset': 'Sunset', 'heart': 'Ruby', 'copper': 'Copper', 'aurora': 'Aurora', 'synthwave': 'Synth',
  'tropical': 'Tropical', 'autumn': 'Autumn', 'halloween': 'Spooky', 'christmas': 'Merry', 'mono': 'Silver',
  'bubblegum': 'Bubblegum', 'fireice': 'Fire & Ice', 'diwali': 'Diwali', 'spring': 'Spring', 'peach': 'Peach',
  'forest': 'Forest', 'ember': 'Ember', 'deepsea': 'Deep Sea', 'desert': 'Desert', 'matrix': 'Matrix', 'cmy': 'Print',
};

/// Alternate colourways for recolourable sprites, per category.
const spriteColourways = <String, List<String>>{
  'Love': ['neon', 'gold', 'candy', 'galaxy', 'sapphire'],
  'Emoji': ['neon', 'candy', 'gold'],
  'Animals': ['tropical', 'candy', 'neon', 'sapphire'],
  'Food & Drink': ['candy', 'mint', 'neon'],
  'Holidays': ['gold', 'neon', 'candy', 'rainbow'],
  'Gaming': ['neon', 'gold', 'cyberpunk', 'toxic'],
  'Symbols': ['neon', 'gold', 'mint', 'candy', 'rainbow', 'blood'],
  'Nature': ['candy', 'sakura', 'gold'],
  'Weather': ['candy', 'neon', 'gold'],
  'Space': ['neon', 'gold', 'candy'],
  'Fire & Energy': ['arctic', 'toxic'],
};

const motionTitle = {
  SpriteMotion.bounce: 'Bounce',
  SpriteMotion.float: 'Float',
};

/// Season/occasion tags inferred from sprite tags, so search and the seasonal
/// shelf find them.
const occasionTags = {
  'christmas': ['winter', 'holiday'],
  'halloween': ['autumn', 'october'],
  'valentine': ['love', 'february'],
  'diwali': ['festival', 'india'],
  'easter': ['spring'],
  'eid': ['ramadan', 'festival'],
  'hanukkah': ['winter', 'festival'],
  'new year': ['celebrate', 'winter'],
  'birthday': ['celebrate', 'party'],
};

String slug(String s) => s
    .toLowerCase()
    .replaceAll('&', 'and')
    .replaceAll(RegExp(r"['’]"), '')
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

List<String> splitTags(String s) =>
    s.split(' ').where((t) => t.isNotEmpty).map((t) => t.replaceAll('_', ' ')).toList();

void main() {
  final starter = Catalog.parse(File('assets/catalog/starter.json').readAsStringSync());
  final out = <LibraryItem>[];
  final ids = <String>{};
  final titles = <String>{};
  final sigs = <String>{};
  final problems = <String>[];

  String sig(LibraryItem i) {
    final keys = i.params.keys.toList()..sort();
    return '${i.generatorId}|${i.paletteId}|${keys.map((k) => '$k=${i.params[k]}').join(',')}';
  }

  void add(LibraryItem i) {
    final g = findGenerator(i.generatorId);
    if (g == null) problems.add('${i.id}: unknown generator ${i.generatorId}');
    if (!palettes.any((p) => p.id == i.paletteId)) problems.add('${i.id}: unknown palette ${i.paletteId}');
    if (g != null) {
      final specs = {for (final s in g.params) s.key: s};
      i.params.forEach((k, v) {
        final s = specs[k];
        if (s == null) {
          problems.add('${i.id}: unknown param $k');
        } else if (v < s.min || v > s.max) {
          problems.add('${i.id}: $k=$v outside ${s.min}..${s.max}');
        }
      });
    }
    if (!ids.add(i.id)) problems.add('duplicate id ${i.id}');
    if (!titles.add(i.title.toLowerCase())) problems.add('duplicate title "${i.title}"');
    if (!sigs.add(sig(i))) problems.add('${i.id}: duplicates another look');
    if (i.tags.isEmpty) problems.add('${i.id}: no tags');
    if (!categoryOrder.contains(i.category)) problems.add('${i.id}: unknown category ${i.category}');
    out.add(i);
  }

  List<String> tagsFor(Iterable<String> base, String palette, [String? extra]) {
    final seen = <String>{};
    return [
      for (final t in [...base, ...splitTags(extra ?? ''), ...splitTags(paletteWords[palette] ?? '')])
        if (seen.add(t.toLowerCase())) t.toLowerCase(),
    ];
  }

  // 1. Starter items, unchanged ids; tags enriched with colour words.
  for (final i in starter.items) {
    add(LibraryItem(
      id: i.id,
      title: i.title,
      category: i.category,
      generatorId: i.generatorId,
      paletteId: i.paletteId,
      params: i.params,
      speed: i.speed,
      tags: tagsFor(i.tags, i.paletteId),
      added: 1,
    ));
  }

  // 2. Curated procedural themes.
  for (final MapEntry(key: genId, value: (cat, baseTags, variants)) in themes.entries) {
    final g = findGenerator(genId);
    if (g == null) {
      problems.add('themes: unknown generator $genId');
      continue;
    }
    for (final v in variants) {
      add(LibraryItem(
        id: slug(v.title),
        title: v.title,
        category: v.cat ?? cat,
        generatorId: genId,
        paletteId: v.palette,
        params: v.params,
        speed: v.speed,
        tags: tagsFor(splitTags(baseTags), v.palette, v.tags),
        added: revision,
      ));
    }
  }
  for (final g in generators) {
    if (!themes.containsKey(g.id)) problems.add('generator ${g.id} has no themes');
  }

  // 3. Sprites: the drawing as authored, then one alternate look.
  var spriteItems = 0;
  for (final sg in spriteGenerators) {
    final s = sg.sprite;
    if (s.source != null) {
      // Public-domain classics: one item each, exactly as drawn, with their
      // attribution notice. Recolours or motion swaps would just be noise.
      final title = titles.contains(s.title.toLowerCase()) ? '${s.title} (Classic)' : s.title;
      add(LibraryItem(
        id: ids.contains(slug(title)) ? 'classic-${slug(title)}' : slug(title),
        title: title,
        category: s.category,
        generatorId: sg.id,
        paletteId: s.palette,
        tags: tagsFor([...s.tags, 'classic', 'public domain', 'pixel art', 'sprite'], s.palette),
        added: classicsRevision,
        notice: s.notice,
      ));
      spriteItems++;
      continue;
    }
    final occasion = <String>[
      for (final MapEntry(:key, :value) in occasionTags.entries)
        if (s.tags.contains(key)) ...value,
    ];
    final base = tagsFor([...s.tags, ...occasion, 'pixel art', 'sprite'], s.palette);
    var title = s.title;
    if (titles.contains(title.toLowerCase())) title = 'Pixel $title';
    final baseId = ids.contains(slug(title)) ? 'pixel-${slug(title)}' : slug(title);
    add(LibraryItem(
      id: baseId,
      title: title,
      category: s.category,
      generatorId: sg.id,
      paletteId: s.palette,
      tags: base,
      added: revision,
    ));
    spriteItems++;
    final ways = [...?spriteColourways[s.category]]..remove(s.palette);
    if (s.recolourable && ways.isNotEmpty) {
      // Two deterministic colourways per recolourable sprite.
      final h = s.id.codeUnits.fold(0, (a, b) => (a * 31 + b) & 0x7fffffff);
      for (var k = 0; k < min(2, ways.length); k++) {
        final pal = ways[(h + k * 3) % ways.length];
        if (out.any((i) => i.generatorId == sg.id && i.paletteId == pal)) continue;
        final t = '${paletteAdjective[pal] ?? pal} ${s.title}';
        if (titles.contains(t.toLowerCase())) continue;
        add(LibraryItem(
          id: slug(t),
          title: t,
          category: s.category,
          generatorId: sg.id,
          paletteId: pal,
          tags: tagsFor([...s.tags, ...occasion, 'pixel art', 'sprite'], pal),
          added: revision,
        ));
        spriteItems++;
      }
    } else if (!s.isBanner) {
      // Fixed-colour drawings get a different motion over a soft glow.
      final alt = s.motion == SpriteMotion.bounce ? SpriteMotion.float : SpriteMotion.bounce;
      final t = '${s.title} (${motionTitle[alt]})';
      add(LibraryItem(
        id: slug(t),
        title: t,
        category: s.category,
        generatorId: sg.id,
        paletteId: s.palette,
        params: {'motion': alt.index.toDouble(), 'backdrop': 0.5},
        tags: tagsFor([...s.tags, ...occasion, 'pixel art', 'sprite', alt.name], s.palette),
        added: revision,
      ));
      spriteItems++;
    } else {
      final pal = s.palette == 'rainbow' ? 'neon' : 'rainbow';
      final t = '${s.title} (${paletteAdjective[pal]})';
      add(LibraryItem(
        id: slug(t),
        title: t,
        category: s.category,
        generatorId: sg.id,
        paletteId: pal,
        tags: tagsFor([...s.tags, ...occasion, 'text', 'banner'], pal),
        added: revision,
      ));
      spriteItems++;
    }
  }

  // Featured ranks.
  final rank = {for (var k = 0; k < featuredIds.length; k++) featuredIds[k]: k};
  for (final id in featuredIds) {
    if (!ids.contains(id)) problems.add('featured: unknown id $id');
  }
  final items = [
    for (final i in out)
      rank.containsKey(i.id)
          ? LibraryItem.fromJson({...i.toJson(), 'featured': rank[i.id]})
          : i,
  ];

  if (problems.isNotEmpty) {
    stderr.writeln(problems.join('\n'));
    exit(1);
  }

  final cats = [for (final c in categoryOrder) if (items.any((i) => i.category == c)) c];
  final catalog = Catalog(items: items, categories: cats);
  final json = const JsonEncoder.withIndent(null).convert(catalog.toJson());
  // One item per line keeps diffs readable without bloating the asset.
  final pretty = json.replaceAll('},{"id"', '},\n{"id"').replaceFirst('"items":[{', '"items":[\n{');
  File('assets/catalog/catalog.json').writeAsStringSync('$pretty\n');

  stdout.writeln('catalog.json: ${items.length} items, ${cats.length} categories, '
      '$spriteItems sprite items, ${items.length - spriteItems} procedural');
  for (final c in cats) {
    stdout.writeln('  ${c.padRight(16)} ${items.where((i) => i.category == c).length}');
  }
}

int min(int a, int b) => a < b ? a : b;
