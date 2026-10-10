import Foundation

// MARK: - Détection de données sensibles (F13, version regex de base, 100 % locale).

enum SensitiveData {
    enum Kind: String, CaseIterable {
        case email, card, iban, apiKey

        var title: String {
            switch self {
            case .email: String(localized: "E-mail")
            case .card: String(localized: "Carte bancaire")
            case .iban: "IBAN"
            case .apiKey: String(localized: "Clé API")
            }
        }
    }

    struct Finding {
        let kind: Kind
        let value: String
    }

    private static let patterns: [(Kind, String, NSRegularExpression.Options)] = [
        (.email, #"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#, .caseInsensitive),
        (.card, #"\b(?:\d[ \−]?){13,19}\b"#, []),
        (.iban, #"\b[A-Z]{2}\d{2}(?:[ ]?[A-Z0-9]{4}){2,6}\b"#, []),
        (.apiKey, #"(?:sk\-|AKIA|ghp_|xox[bap]\-|AIza)[A-Za-z0-9_\-]{8,}"#, []),
    ]

    /// Retourne les occurrences détectées, sans jamais quitter l'appareil.
    static func findings(in text: String) -> [Finding] {
        var results: [Finding] = []
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for (kind, pattern, options) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { continue }
            for match in regex.matches(in: text, options: [], range: range) {
                guard let swiftRange = Range(match.range, in: text) else { continue }
                let value = String(text[swiftRange])
                if kind == .card, !looksLikeCard(value) { continue }
                results.append(Finding(kind: kind, value: value))
            }
        }
        return results
    }

    private static func looksLikeCard(_ value: String) -> Bool {
        let digits = value.filter(\.isNumber)
        guard (13...19).contains(digits.count) else { return false }
        // Contrôle de Luhn pour écarter les faux positifs.
        var sum = 0
        for (index, character) in digits.reversed().enumerated() {
            guard let digit = character.wholeNumberValue else { return false }
            if index % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }
}
