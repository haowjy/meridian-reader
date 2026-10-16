import Foundation

/// How many words a text holds, for every page: web pages, chapters, and the cutting of a book
/// into chapters. A word is a run of non-space characters holding a letter or digit. Each Chinese
/// or Japanese character counts as a word, since those scripts don't put spaces between words.
enum WordCount {
    static func count(_ text: String) -> Int {
        var count = 0
        var inToken = false
        var tokenHasWordCharacter = false
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace {
                if inToken, tokenHasWordCharacter { count += 1 }
                inToken = false
                tokenHasWordCharacter = false
            } else if isIdeographic(scalar) {
                if inToken, tokenHasWordCharacter { count += 1 }
                count += 1
                inToken = false
                tokenHasWordCharacter = false
            } else {
                inToken = true
                if isWordCharacter(scalar) { tokenHasWordCharacter = true }
            }
        }
        if inToken, tokenHasWordCharacter { count += 1 }
        return count
    }

    static func isWordCharacter(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isAlphabetic || scalar.properties.numericType != nil
    }

    static func isIdeographic(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2A6DF: true
        default: false
        }
    }
}
