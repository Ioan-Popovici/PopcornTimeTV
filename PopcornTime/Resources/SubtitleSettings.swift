

import Foundation
import SwiftUI

class SubtitleSettings: Codable, @unchecked Sendable {
    
    enum Size: Float, CaseIterable, Codable {
        case small = 20.0
        case medium = 16.0
        case mediumLarge = 12.0
        case large = 6.0
        
        var localizedString: String {
            switch self {
            case .small:
                return "Small".localized
            case .medium:
                return "Medium".localized
            case .mediumLarge:
                return "Medium Large".localized
            case .large:
                return "Large".localized
            }
        }
    }
    
    static var encodings: [String: String] {
        return [
            "Universal (UTF-8)": "UTF-8",
            "Universal (UTF-16)": "UTF-16",
            "Universal (big endian UTF-16)": "UTF-16BE",
            "Universal (little endian UTF-16)": "UTF-16LE",
            "Universal Chinese (GB18030)": "GB18030",
            "Western European (Latin-1)": "ISO-8859-1",
            "Western European (Latin-9)": "ISO-8859-15",
            "Western European (Windows-1252)": "Windows-1252",
            "Western European (IBM 00850)": "IBM850",
            "Eastern European (Latin-2)": "ISO-8859-2",
            "Eastern European (Windows-1250)": "Windows-1250",
            "Esperanto (Latin-3)": "ISO-8859-3",
            "Nordic (Latin-6)": "ISO-8859-10",
            "Cyrillic (Windows-1251)": "Windows-1251",
            "Russian (KOI8-R)": "KOI8-R",
            "Ukrainian (KOI8-U)": "KOI8-U",
            "Arabic (ISO 8859-6)": "ISO-8859-6",
            "Arabic (Windows-1256)": "Windows-1256",
            "Greek (ISO 8859-7)": "ISO-8859-7",
            "Greek (Windows-1253)": "Windows-1253",
            "Hebrew (ISO 8859-8)": "ISO-8859-8",
            "Hebrew (Windows-1255)": "Windows-1255",
            "Turkish (ISO 8859-9)": "ISO-8859-9",
            "Turkish (Windows-1254)": "Windows-1254",
            "Thai (TIS 620-2533/ISO 8859-11)": "ISO-8859-11",
            "Thai (Windows-874)": "Windows-874",
            "Baltic (Latin-7)": "ISO-8859-13",
            "Baltic (Windows-1257)": "Windows-1257",
            "Celtic (Latin-8)": "ISO-8859-14",
            "South-Eastern European (Latin-10)": "ISO-8859-16",
            "Simplified Chinese (ISO-2022-CN-EXT)": "ISO-2022-CN-EXT",
            "Simplified Chinese Unix (EUC-CN)": "EUC-CN",
            "Japanese (7-bits JIS/ISO-2022-JP-2)": "ISO-2022-JP-2",
            "Japanese Unix (EUC-JP)": "EUC-JP",
            "Japanese (Shift JIS)": "Shift_JIS",
            "Korean (EUC-KR/CP949)": "CP949",
            "Korean (ISO-2022-KR)": "ISO-2022-KR",
            "Traditional Chinese (Big5)": "Big5",
            "Traditional Chinese Unix (EUC-TW)": "ISO-2022-TW",
            "Hong-Kong Supplementary (HKSCS)": "Big5-HKSCS",
            "Vietnamese (VISCII)": "VISCII",
            "Vietnamese (Windows-1258)": "Windows-1258"
        ]
    }
    
    var size: Size = .medium
    var color: SubtitleColor = .white
    var encoding: String = "UTF-8"
    var language: String? = nil
    var fontName: String = defaultFont.name
    var fontFamilyName: String = defaultFont.familyName
    var style: FontStyle = .normal
    
    enum CodingKeys: String, CodingKey {
        case size, color, encoding, language, fontName, fontFamilyName, style
    }
    
    // not saved
    var subtitlesSelectedForVideo: [Any] = Array()
    
    static let shared = Session.subtitleSettings.flatMap({ try? JSONDecoder().decode(SubtitleSettings.self, from: $0) }) ?? SubtitleSettings()
    
    func save() {
        Session.subtitleSettings = try? JSONEncoder().encode(self)
    }
    
    static var defaultFont: (name: String, familyName: String) {
        #if os(iOS) || os(tvOS)
        let font = UIFont.systemFont(ofSize: 20)
        return (font.fontName, font.familyName)
        #elseif os(macOS)
        let font = NSFont.systemFont(ofSize: 20)
        return (font.fontName, font.familyName ?? "N/A")
        #endif
    }
}


extension Font {
    static var familyNames: [String] {
        #if os(iOS) || os(tvOS)
        return UIFont.familyNames
        #elseif os(macOS)
        return NSFontManager.shared.availableFontFamilies
        #endif
    }
    
    static func fontName(familyName: String) -> String? {
        #if os(iOS) || os(tvOS)
        return UIFont.fontNames(forFamilyName: familyName).first
        #elseif os(macOS)
        return NSFontManager.shared.font(withFamily: familyName, traits: [], weight: 2, size: 20)?.fontName
        #endif
    }
}
