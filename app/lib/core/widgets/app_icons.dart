import 'package:flutter/widgets.dart';

/// One place for every icon so the app speaks a single visual language.
///
/// Glyphs come from the Phosphor icon font (MIT), bundled in assets/fonts.
abstract final class AppIcons {
  // Navigation
  static const home = IconData(0xe2c2, fontFamily: 'PhosphorRegular');
  static const homeActive = IconData(0xe2c2, fontFamily: 'PhosphorFill');
  static const communities = IconData(0xe68e, fontFamily: 'PhosphorRegular');
  static const communitiesActive = IconData(0xe68e, fontFamily: 'PhosphorFill');
  static const events = IconData(0xe10a, fontFamily: 'PhosphorRegular');
  static const eventsActive = IconData(0xe10a, fontFamily: 'PhosphorFill');
  static const reels = IconData(0xe3d2, fontFamily: 'PhosphorRegular');
  static const reelsActive = IconData(0xe3d2, fontFamily: 'PhosphorFill');
  static const chat = IconData(0xe17e, fontFamily: 'PhosphorRegular');
  static const chatActive = IconData(0xe17e, fontFamily: 'PhosphorFill');

  // Actions
  static const search = IconData(0xe30c, fontFamily: 'PhosphorRegular');
  static const bell = IconData(0xe0ce, fontFamily: 'PhosphorRegular');
  static const plus = IconData(0xe3d4, fontFamily: 'PhosphorRegular');
  static const plusBold = IconData(0xe3d4, fontFamily: 'PhosphorBold');
  static const close = IconData(0xe4f6, fontFamily: 'PhosphorRegular');
  static const back = IconData(0xe138, fontFamily: 'PhosphorRegular');
  static const forward = IconData(0xe13a, fontFamily: 'PhosphorRegular');
  static const down = IconData(0xe136, fontFamily: 'PhosphorRegular');
  static const more = IconData(0xe1fe, fontFamily: 'PhosphorRegular');
  static const moreVertical = IconData(0xe208, fontFamily: 'PhosphorRegular');
  static const edit = IconData(0xe3b4, fontFamily: 'PhosphorRegular');
  static const trash = IconData(0xe4a6, fontFamily: 'PhosphorRegular');
  static const share = IconData(0xed52, fontFamily: 'PhosphorRegular');
  static const send = IconData(0xe396, fontFamily: 'PhosphorFill');
  static const link = IconData(0xe2e2, fontFamily: 'PhosphorRegular');
  static const copy = IconData(0xe1ca, fontFamily: 'PhosphorRegular');
  static const settings = IconData(0xe270, fontFamily: 'PhosphorRegular');
  static const filter = IconData(0xe434, fontFamily: 'PhosphorRegular');
  static const check = IconData(0xe182, fontFamily: 'PhosphorBold');
  static const checkCircle = IconData(0xe184, fontFamily: 'PhosphorFill');
  static const info = IconData(0xe2ce, fontFamily: 'PhosphorRegular');
  static const signOut = IconData(0xe42a, fontFamily: 'PhosphorRegular');
  static const camera = IconData(0xe10e, fontFamily: 'PhosphorRegular');
  static const image = IconData(0xe2ca, fontFamily: 'PhosphorRegular');
  static const video = IconData(0xe4da, fontFamily: 'PhosphorRegular');
  static const paperclip = IconData(0xe39a, fontFamily: 'PhosphorRegular');
  static const file = IconData(0xe23a, fontFamily: 'PhosphorRegular');
  static const download = IconData(0xe20c, fontFamily: 'PhosphorRegular');
  static const reply = IconData(0xe024, fontFamily: 'PhosphorRegular');
  static const smiley = IconData(0xe436, fontFamily: 'PhosphorRegular');
  static const eye = IconData(0xe220, fontFamily: 'PhosphorRegular');
  static const eyeSlash = IconData(0xe224, fontFamily: 'PhosphorRegular');
  static const lock = IconData(0xe308, fontFamily: 'PhosphorRegular');
  static const globe = IconData(0xe28a, fontFamily: 'PhosphorRegular');
  static const pin = IconData(0xe3e2, fontFamily: 'PhosphorFill');
  static const pinOutline = IconData(0xe3e2, fontFamily: 'PhosphorRegular');
  static const mute = IconData(0xe0d4, fontFamily: 'PhosphorRegular');
  static const sparkle = IconData(0xe6a2, fontFamily: 'PhosphorFill');

  // Content
  static const heart = IconData(0xe2a8, fontFamily: 'PhosphorRegular');
  static const heartFill = IconData(0xe2a8, fontFamily: 'PhosphorFill');
  static const comment = IconData(0xe168, fontFamily: 'PhosphorRegular');
  static const bookmark = IconData(0xe0ea, fontFamily: 'PhosphorRegular');
  static const bookmarkFill = IconData(0xe0ea, fontFamily: 'PhosphorFill');
  static const followPost = IconData(0xe5e8, fontFamily: 'PhosphorRegular');
  static const flag = IconData(0xe244, fontFamily: 'PhosphorRegular');
  static const block = IconData(0xe3de, fontFamily: 'PhosphorRegular');
  static const poll = IconData(0xe150, fontFamily: 'PhosphorRegular');
  static const question = IconData(0xe3e8, fontFamily: 'PhosphorRegular');
  static const megaphone = IconData(0xe324, fontFamily: 'PhosphorRegular');
  static const trophy = IconData(0xe67e, fontFamily: 'PhosphorRegular');
  static const trophyFill = IconData(0xe67e, fontFamily: 'PhosphorFill');
  static const textPost = IconData(0xe6ee, fontFamily: 'PhosphorRegular');
  static const hash = IconData(0xe2a2, fontFamily: 'PhosphorRegular');
  static const at = IconData(0xe0ac, fontFamily: 'PhosphorRegular');
  static const anonymous = IconData(0xe83e, fontFamily: 'PhosphorFill');
  static const anonymousOutline = IconData(0xe83e, fontFamily: 'PhosphorRegular');
  static const crown = IconData(0xe614, fontFamily: 'PhosphorFill');
  static const roles = IconData(0xe4cc, fontFamily: 'PhosphorRegular');
  static const verified = IconData(0xe606, fontFamily: 'PhosphorFill');
  static const shield = IconData(0xe40c, fontFamily: 'PhosphorRegular');

  // Places and people
  static const mapPin = IconData(0xe316, fontFamily: 'PhosphorRegular');
  static const clock = IconData(0xe19a, fontFamily: 'PhosphorRegular');
  static const calendarPlus = IconData(0xe714, fontFamily: 'PhosphorRegular');
  static const ticket = IconData(0xe490, fontFamily: 'PhosphorRegular');
  static const users = IconData(0xe4d6, fontFamily: 'PhosphorRegular');
  static const user = IconData(0xe4c2, fontFamily: 'PhosphorRegular');
  static const userPlus = IconData(0xe4d0, fontFamily: 'PhosphorRegular');
  static const graduation = IconData(0xe62c, fontFamily: 'PhosphorRegular');
  static const buildings = IconData(0xe102, fontFamily: 'PhosphorRegular');
  static const ranking = IconData(0xed62, fontFamily: 'PhosphorRegular');
  static const chartLine = IconData(0xe156, fontFamily: 'PhosphorRegular');
  static const monitor = IconData(0xe32e, fontFamily: 'PhosphorRegular');
  static const briefcase = IconData(0xe0ee, fontFamily: 'PhosphorRegular');

  // Calls and rooms
  static const phone = IconData(0xe3b8, fontFamily: 'PhosphorRegular');
  static const phoneFill = IconData(0xe3b8, fontFamily: 'PhosphorFill');
  static const phoneOff = IconData(0xe3c2, fontFamily: 'PhosphorFill');
  static const videoCall = IconData(0xe4da, fontFamily: 'PhosphorRegular');
  static const videoOff = IconData(0xe4dc, fontFamily: 'PhosphorRegular');
  static const mic = IconData(0xe326, fontFamily: 'PhosphorRegular');
  static const micOff = IconData(0xe328, fontFamily: 'PhosphorRegular');
  static const speaker = IconData(0xe44a, fontFamily: 'PhosphorRegular');
  static const flipCamera = IconData(0xe7a4, fontFamily: 'PhosphorRegular');
  static const headphones = IconData(0xe2a6, fontFamily: 'PhosphorRegular');
  static const waveform = IconData(0xe802, fontFamily: 'PhosphorRegular');

  // Room kinds
  static const book = IconData(0xe8f2, fontFamily: 'PhosphorRegular');
  static const code = IconData(0xe1bc, fontFamily: 'PhosphorRegular');
  static const gamepad = IconData(0xe26e, fontFamily: 'PhosphorRegular');
  static const lightning = IconData(0xe2de, fontFamily: 'PhosphorRegular');
  static const flagBanner = IconData(0xe622, fontFamily: 'PhosphorRegular');

  // Misc
  static const sun = IconData(0xe472, fontFamily: 'PhosphorRegular');
  static const moon = IconData(0xe330, fontFamily: 'PhosphorRegular');
  static const device = IconData(0xe1e0, fontFamily: 'PhosphorRegular');
  static const warning = IconData(0xe4e2, fontFamily: 'PhosphorRegular');
  static const wifiOff = IconData(0xe4f2, fontFamily: 'PhosphorRegular');
  static const play = IconData(0xe3d0, fontFamily: 'PhosphorFill');
  static const pause = IconData(0xe39e, fontFamily: 'PhosphorFill');
  static const volumeOff = IconData(0xe45a, fontFamily: 'PhosphorFill');
  static const volumeOn = IconData(0xe44a, fontFamily: 'PhosphorFill');
  static const chatText = IconData(0xe17a, fontFamily: 'PhosphorRegular');
  static const newChat = IconData(0xe34c, fontFamily: 'PhosphorRegular');
}
