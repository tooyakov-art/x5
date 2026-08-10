import Foundation

struct CISCity: Decodable, Identifiable, Hashable {
    let country: String
    let city: String
    let ascii: String
    let population: Int
    var id: String { "\(country):\(city)" }
}

enum CISLocations {
    static let countries: [(code: String, name: String)] = [
        ("KZ", "Казахстан"), ("RU", "Россия"), ("UZ", "Узбекистан"),
        ("KG", "Кыргызстан"), ("TJ", "Таджикистан"), ("TM", "Туркменистан"),
        ("AZ", "Азербайджан"), ("AM", "Армения"), ("BY", "Беларусь"),
        ("MD", "Молдова"), ("GE", "Грузия"), ("UA", "Украина")
    ]

    static let cities: [CISCity] = {
        guard let url = Bundle.main.url(forResource: "cis-cities", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rows = try? JSONDecoder().decode([CISCity].self, from: data)
        else { return [] }
        return rows
    }()

    static func search(country: String, query: String, limit: Int = 12) -> [CISCity] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        guard !country.isEmpty else { return [] }
        return cities.lazy.filter { row in
            guard row.country == country else { return false }
            if needle.isEmpty { return true }
            return row.city.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(needle)
                || row.ascii.lowercased().contains(needle.lowercased())
        }.prefix(limit).map { $0 }
    }
}
