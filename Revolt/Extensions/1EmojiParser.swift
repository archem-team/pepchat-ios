//
//  EmojiParser.swift
//  Revolt
//
//  Created by Assistant on 2025-01-15.
//

import Foundation
import UIKit
import Types

/// Emoji dictionary mapping shortcodes to Unicode emoji characters
/// Based on the TypeScript implementation from emoji.tsx
class EmojiParser {
    
    static let emojiDictionary: [String: String] = [
        "100": "💯",
        "1234": "🔢",
        "grinning": "😀",
        "smiley": "😃",
        "smile": "😄",
        "grin": "😁",
        "laughing": "😆",
        "satisfied": "😆",
        "sweat_smile": "😅",
        "rofl": "🤣",
        "joy": "😂",
        "slightly_smiling_face": "🙂",
        "upside_down_face": "🙃",
        "wink": "😉",
        "blush": "😊",
        "innocent": "😇",
        "smiling_face_with_three_hearts": "🥰",
        "heart_eyes": "😍",
        "star_struck": "🤩",
        "kissing_heart": "😘",
        "kissing": "😗",
        "relaxed": "☺️",
        "kissing_closed_eyes": "😚",
        "kissing_smiling_eyes": "😙",
        "smiling_face_with_tear": "🥲",
        "yum": "😋",
        "stuck_out_tongue": "😛",
        "stuck_out_tongue_winking_eye": "😜",
        "zany_face": "🤪",
        "stuck_out_tongue_closed_eyes": "😝",
        "money_mouth_face": "🤑",
        "hugs": "🤗",
        "hand_over_mouth": "🤭",
        "shushing_face": "🤫",
        "thinking": "🤔",
        "zipper_mouth_face": "🤐",
        "raised_eyebrow": "🤨",
        "neutral_face": "😐",
        "expressionless": "😑",
        "no_mouth": "😶",
        "smirk": "😏",
        "unamused": "😒",
        "roll_eyes": "🙄",
        "grimacing": "😬",
        "lying_face": "🤥",
        "relieved": "😌",
        "pensive": "😔",
        "sleepy": "😪",
        "drooling_face": "🤤",
        "sleeping": "😴",
        "mask": "😷",
        "face_with_thermometer": "🤒",
        "face_with_head_bandage": "🤕",
        "nauseated_face": "🤢",
        "vomiting_face": "🤮",
        "sneezing_face": "🤧",
        "hot_face": "🥵",
        "cold_face": "🥶",
        "woozy_face": "🥴",
        "dizzy_face": "😵",
        "exploding_head": "🤯",
        "cowboy_hat_face": "🤠",
        "partying_face": "🥳",
        "disguised_face": "🥸",
        "sunglasses": "😎",
        "nerd_face": "🤓",
        "monocle_face": "🧐",
        "confused": "😕",
        "worried": "😟",
        "slightly_frowning_face": "🙁",
        "frowning_face": "☹️",
        "open_mouth": "😮",
        "hushed": "😯",
        "astonished": "😲",
        "flushed": "😳",
        "pleading_face": "🥺",
        "frowning": "😦",
        "anguished": "😧",
        "fearful": "😨",
        "cold_sweat": "😰",
        "disappointed_relieved": "😥",
        "cry": "😢",
        "sob": "😭",
        "scream": "😱",
        "confounded": "😖",
        "persevere": "😣",
        "disappointed": "😞",
        "sweat": "😓",
        "weary": "😩",
        "tired_face": "😫",
        "yawning_face": "🥱",
        "triumph": "😤",
        "rage": "😡",
        "pout": "😡",
        "angry": "😠",
        "cursing_face": "🤬",
        "smiling_imp": "😈",
        "imp": "👿",
        "skull": "💀",
        "skull_and_crossbones": "☠️",
        "hankey": "💩",
        "poop": "💩",
        "shit": "💩",
        "clown_face": "🤡",
        "japanese_ogre": "👹",
        "japanese_goblin": "👺",
        "ghost": "👻",
        "alien": "👽",
        "space_invader": "👾",
        "robot": "🤖",
        "smiley_cat": "😺",
        "smile_cat": "😸",
        "joy_cat": "😹",
        "heart_eyes_cat": "😻",
        "smirk_cat": "😼",
        "kissing_cat": "😽",
        "scream_cat": "🙀",
        "crying_cat_face": "😿",
        "pouting_cat": "😾",
        "see_no_evil": "🙈",
        "hear_no_evil": "🙉",
        "speak_no_evil": "🙊",
        "kiss": "💋",
        "love_letter": "💌",
        "cupid": "💘",
        "gift_heart": "💝",
        "sparkling_heart": "💖",
        "heartpulse": "💗",
        "heartbeat": "💓",
        "revolving_hearts": "💞",
        "two_hearts": "💕",
        "heart_decoration": "💟",
        "heavy_heart_exclamation": "❣️",
        "broken_heart": "💔",
        "heart": "❤️",
        "orange_heart": "🧡",
        "yellow_heart": "💛",
        "green_heart": "💚",
        "blue_heart": "💙",
        "purple_heart": "💜",
        "brown_heart": "🤎",
        "black_heart": "🖤",
        "white_heart": "🤍",
        "anger": "💢",
        "boom": "💥",
        "collision": "💥",
        "dizzy": "💫",
        "sweat_drops": "💦",
        "dash": "💨",
        "hole": "🕳️",
        "bomb": "💣",
        "speech_balloon": "💬",
        "eye_speech_bubble": "👁️‍🗨️",
        "left_speech_bubble": "🗨️",
        "right_anger_bubble": "🗯️",
        "thought_balloon": "💭",
        "zzz": "💤",
        "wave": "👋",
        "raised_back_of_hand": "🤚",
        "raised_hand_with_fingers_splayed": "🖐️",
        "hand": "✋",
        "raised_hand": "✋",
        "vulcan_salute": "🖖",
        "ok_hand": "👌",
        "pinched_fingers": "🤌",
        "pinching_hand": "🤏",
        "v": "✌️",
        "crossed_fingers": "🤞",
        "love_you_gesture": "🤟",
        "metal": "🤘",
        "call_me_hand": "🤙",
        "point_left": "👈",
        "point_right": "👉",
        "point_up_2": "👆",
        "middle_finger": "🖕",
        "fu": "🖕",
        "point_down": "👇",
        "point_up": "☝️",
        "+1": "👍",
        "thumbsup": "👍",
        "-1": "👎",
        "thumbsdown": "👎",
        "fist_raised": "✊",
        "fist": "✊",
        "fist_oncoming": "👊",
        "facepunch": "👊",
        "punch": "👊",
        "fist_left": "🤛",
        "fist_right": "🤜",
        "clap": "👏",
        "raised_hands": "🙌",
        "open_hands": "👐",
        "palms_up_together": "🤲",
        "handshake": "🤝",
        "pray": "🙏",
        "writing_hand": "✍️",
        "nail_care": "💅",
        "selfie": "🤳",
        "muscle": "💪",
        // Add more popular emojis - keeping it manageable for now
        "fire": "🔥",
        "water_drop": "💧",
        "ocean": "🌊",
        "thunder": "⚡",
        "star": "⭐",
        "sun": "☀️",
        "moon": "🌙",
        "rainbow": "🌈",
        "snowflake": "❄️",
        "coffee": "☕",
        "pizza": "🍕",
        "hamburger": "🍔",
        "beer": "🍺",
        "wine_glass": "🍷",
        "cake": "🎂",
        "gift": "🎁",
        "football": "⚽",
        "basketball": "🏀",
        "car": "🚗",
        "airplane": "✈️",
        "house": "🏠",
        "tree": "🌳",
        "flower": "🌸",
        "dog": "🐶",
        "cat": "🐱",
        "music": "🎵",
        "book": "📖",
        "phone": "📱",
        "computer": "💻",
        "tv": "📺",
        "camera": "📷",
        "money": "💰",
        "gem": "💎",
        "key": "🔑",
        "lock": "🔒",
        "bulb": "💡",
        "bomb": "💣",
        "gun": "🔫",
        "knife": "🔪",
        "pill": "💊",
        "syringe": "💉",
        "rocket": "🚀",
        "satellite": "📡",
        "hourglass": "⌛",
        "clock": "🕐",
        "watch": "⌚",
        "calendar": "📅",
        "envelope": "✉️",
        "package": "📦",
        "mailbox": "📫",
        "pencil": "✏️",
        "pen": "🖊️",
        "scissors": "✂️",
        "paperclip": "📎",
        "folder": "📁",
        "file": "📄",
        "newspaper": "📰",
        "bookmark": "🔖",
        "trash": "🗑️",
        "recycle": "♻️",
        "warning": "⚠️",
        "construction": "🚧",
        "sos": "🆘",
        "fire_engine": "🚒",
        "ambulance": "🚑",
        "police_car": "🚓",
        "medal": "🏅",
        "trophy": "🏆",
        "crown": "👑",
        "ring": "💍",
        "diamond": "💎",
        "flag": "🏁",
        "loudspeaker": "📢",
        "bell": "🔔",
        "mute": "🔇",
        "battery": "🔋",
        "electric_plug": "🔌",
        "flashlight": "🔦",
        "candle": "🕯️",
        "wrench": "🔧",
        "hammer": "🔨",
        "gear": "⚙️",
        "magnet": "🧲",
        "telescope": "🔭",
        "microscope": "🔬",
        "syringe": "💉",
        "thermometer": "🌡️",
        "scales": "⚖️",
        "link": "🔗",
        "chains": "⛓️",
        "anchor": "⚓",
        "wheel": "⚙️",
        "gear": "⚙️"
    ]
    
    /// Custom emoji dictionary for Revolt-specific custom emojis
    static let customEmojiDictionary: [String: String] = [
        "1984": "custom:1984.gif",
        "KekW": "custom:KekW.png",
        "amogus": "custom:amogus.gif",
        "awaa": "custom:awaa.png",
        "boohoo": "custom:boohoo.png",
        "boohoo_goes_hard": "custom:boohoo_goes_hard.png",
        "boohoo_shaken": "custom:boohoo_shaken.png",
        "cat_arrival": "custom:cat_arrival.gif",
        "cat_awson": "custom:cat_awson.png",
        "cat_blob": "custom:cat_blob.png",
        "cat_bonk": "custom:cat_bonk.png",
        "cat_concern": "custom:cat_concern.png",
        "cat_fast": "custom:cat_fast.gif",
        "cat_kitty": "custom:cat_kitty.png",
        "cat_lick": "custom:cat_lick.gif",
        "cat_not_like": "custom:cat_not_like.png",
        "cat_put": "custom:cat_put.gif",
        "cat_pwease": "custom:cat_pwease.png",
        "cat_rage": "custom:cat_rage.png",
        "cat_sad": "custom:cat_sad.png",
        "cat_snuff": "custom:cat_snuff.gif",
        "cat_spin": "custom:cat_spin.gif",
        "cat_squish": "custom:cat_squish.gif",
        "cat_stare": "custom:cat_stare.gif",
        "cat_steal": "custom:cat_steal.gif",
        "cat_sussy": "custom:cat_sussy.gif",
        "clueless": "custom:clueless.png",
        "death": "custom:death.gif",
        "developers": "custom:developers.gif",
        "fastwawa": "custom:fastwawa.gif",
        "ferris": "custom:ferris.png",
        "ferris_bongo": "custom:ferris_bongo.gif",
        "ferris_nom": "custom:ferris_nom.png",
        "ferris_pensive": "custom:ferris_pensive.png",
        "ferris_unsafe": "custom:ferris_unsafe.png",
        "flesh": "custom:flesh.png",
        "flooshed": "custom:flooshed.png",
        "flosh": "custom:flosh.png",
        "flushee": "custom:flushee.png",
        "forgor": "custom:forgor.png",
        "hollow": "custom:hollow.png",
        "john": "custom:john.png",
        "lightspeed": "custom:lightspeed.png",
        "little_guy": "custom:little_guy.png",
        "lmaoooo": "custom:lmaoooo.gif",
        "lol": "custom:lol.png",
        "looking": "custom:looking.gif",
        "marie": "custom:marie.png",
        "marie_furret": "custom:marie_furret.gif",
        "marie_smug": "custom:marie_smug.png",
        "megumin": "custom:megumin.png",
        "michi_above": "custom:michi_above.png",
        "michi_awww": "custom:michi_awww.gif",
        "michi_drag": "custom:michi_drag.gif",
        "michi_flustered": "custom:michi_flustered.png",
        "michi_glare": "custom:michi_glare.png",
        "michi_sus": "custom:michi_sus.png",
        "monkaS": "custom:monkaS.png",
        "monkaStare": "custom:monkaStare.png",
        "monkey_grr": "custom:monkey_grr.png",
        "monkey_pensive": "custom:monkey_pensive.png",
        "monkey_zany": "custom:monkey_zany.png",
        "nazu_sit": "custom:nazu_sit.png",
        "nazu_sus": "custom:nazu_sus.png",
        "ok_and": "custom:ok_and.gif",
        "owo": "custom:owo.png",
        "pat": "custom:pat.png",
        "pointThink": "custom:pointThink.png",
        "rainbowHype": "custom:rainbowHype.gif",
        "rawr": "custom:rawr.png",
        "rember": "custom:rember.png",
        "revolt": "custom:revolt.png",
        "sickly": "custom:sickly.png",
        "stare": "custom:stare.png",
        "tfyoulookingat": "custom:tfyoulookingat.png",
        "thanks": "custom:thanks.png",
        "thonk": "custom:thonk.png",
        "trol": "custom:trol.png",
        "troll_smile": "custom:troll_smile.gif",
        "uber": "custom:uber.png",
        "ubertroll": "custom:ubertroll.png",
        "verycool": "custom:verycool.png",
        "verygood": "custom:verygood.png",
        "wawafast": "custom:wawafast.gif",
        "wawastance": "custom:wawastance.png",
        "yeahokayyy": "custom:yeahokayyy.png",
        "yed": "custom:yed.png",
        "yems": "custom:yems.png",
        "michael": "custom:michael.gif",
        "charle": "custom:charle.gif",
        "sadge": "custom:sadge.webp",
        "sus": "custom:sus.webp",
        "chade": "custom:chade.gif",
        "gigachad": "custom:gigachad.webp",
        "sippy": "custom:sippy.webp",
        "ayame_heart": "custom:ayame_heart.png",
        "catgirl_peek": "custom:catgirl_peek.png",
        "girl_happy": "custom:girl_happy.png",
        "hug_plushie": "custom:hug_plushie.png",
        "huggies": "custom:huggies.png",
        "noted": "custom:noted.gif",
        "waving": "custom:waving.png"
    ]
    
    /// Parse emoji shortcode and return the appropriate emoji or URL
    /// Based on the TypeScript parseEmoji function
    static func parseEmoji(_ emoji: String, apiInfo: ApiInfo? = nil) -> String {
        if emoji.hasPrefix("custom:") {
            let filename = String(emoji.dropFirst(7)) // Remove "custom:" prefix
            // Use dynamic endpoint if available, fallback to static URL
            if let apiInfo = apiInfo {
                return "\(apiInfo.features.autumn.url)/emojis/\(filename)"
            } else {
                return "https://dl.insrt.uk/projects/revolt/emotes/\(filename)"
            }
        }
        
        // For Unicode emojis, we need to convert them to codepoints
        let codepoint = toCodePoint(emoji)
        // Use dynamic endpoint if available, fallback to static URL
        if let apiInfo = apiInfo {
            return "\(apiInfo.features.autumn.url)/emoji/mutant/\(codepoint).svg"
        } else {
            return "https://static.revolt.chat/emoji/mutant/\(codepoint).svg"
        }
    }
    
    /// Convert Unicode emoji to codepoint string
    /// Based on the TypeScript toCodePoint function
    private static func toCodePoint(_ rune: String) -> String {
        let codePoints = getCodePoints(rune)
        return codePoints.map { String($0, radix: 16) }.joined(separator: "-")
    }
    
    /// Get Unicode code points from emoji string
    /// Based on the TypeScript codePoints function
    private static func getCodePoints(_ rune: String) -> [UInt32] {
        var pairs: [UInt32] = []
        let scalars = rune.unicodeScalars
        
        for scalar in scalars {
            // Skip variation selectors (like \uFE0F) similar to TypeScript
            if scalar.value == 0xFE0F {
                continue
            }
            pairs.append(scalar.value)
        }
        
        return pairs
    }
    
    /// Find emoji by shortcode (like :smile:, :1234:, etc.)
    static func findEmojiByShortcode(_ shortcode: String) -> String? {
        let cleanShortcode = shortcode.trimmingCharacters(in: CharacterSet(charactersIn: ":"))

        // First check exact match
        if let unicodeEmoji = emojiDictionary[cleanShortcode] {
            return unicodeEmoji
        }
        if let customEmoji = customEmojiDictionary[cleanShortcode] {
            return customEmoji
        }
        
        // Then try with normalized underscores
        let collapsedUnderscores = cleanShortcode.replacingOccurrences(of: "_{2,}", with: "_", options: .regularExpression)
        if collapsedUnderscores != cleanShortcode {
            if let unicodeEmoji = emojiDictionary[collapsedUnderscores] {
                return unicodeEmoji
            }
            if let customEmoji = customEmojiDictionary[collapsedUnderscores] {
                return customEmoji
            }
        }

        return nil
    }
    
    /// Process text and replace emoji shortcodes with actual emojis
    static func processEmojiShortcodes(in text: String) -> String {
        // Pattern to match emoji shortcodes like :smile:, :1234:, etc.
        let pattern = ":([a-zA-Z0-9_+-]+):"
        
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let nsText = text as NSString
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
            
            var processedText = text
            
            // Process matches in reverse order to maintain correct indices
            for match in matches.reversed() {
                let fullRange = match.range
                let shortcodeRange = match.range(at: 1)
                
                let fullMatch = nsText.substring(with: fullRange)
                let shortcode = nsText.substring(with: shortcodeRange)
                
                if let emoji = findEmojiByShortcode(shortcode) {
                    // For custom emojis, we keep the shortcode format for now
                    // The actual replacement with images will be handled elsewhere
                    if emoji.hasPrefix("custom:") {
                        // Keep as is for custom emojis - they'll be processed separately
                        continue
                    } else {
                        // Replace with Unicode emoji
                        let startIndex = processedText.index(processedText.startIndex, offsetBy: fullRange.location)
                        let endIndex = processedText.index(startIndex, offsetBy: fullRange.length)
                        processedText.replaceSubrange(startIndex..<endIndex, with: emoji)
                    }
                }
            }
            
            return processedText
        } catch {
            print("Error processing emoji shortcodes: \(error)")
            return text
        }
    }
    
    /// Check if a string is a valid emoji shortcode
    static func isEmojiShortcode(_ text: String) -> Bool {
        return text.hasPrefix(":") && text.hasSuffix(":") && text.count > 2
    }
    
    /// Extract shortcode from emoji format (remove colons)
    static func extractShortcode(_ text: String) -> String {
        return text.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
    }
}