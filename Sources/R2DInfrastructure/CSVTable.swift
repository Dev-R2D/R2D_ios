import Foundation

enum CSVTable {
    static func rows(from data: Data) throws -> [[String: String]] {
        guard var text = String(data: data, encoding: .utf8) else { throw CSVError.invalidEncoding }
        text = text.replacingOccurrences(of: "\u{feff}", with: "")
        let records = parse(text).filter { !$0.allSatisfy(\.isEmpty) }
        guard let headers = records.first, !headers.isEmpty else { throw CSVError.missingHeader }
        return records.dropFirst().map { values in
            Dictionary(uniqueKeysWithValues: headers.enumerated().map { index, header in
                (header.trimmingCharacters(in: .whitespacesAndNewlines), index < values.count ? values[index].trimmingCharacters(in: .whitespacesAndNewlines) : "")
            })
        }
    }

    private static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == "\"" {
                let next = text.index(after: index)
                if quoted, next < text.endIndex, text[next] == "\"" { field.append("\""); index = next } else { quoted.toggle() }
            } else if character == ",", !quoted { row.append(field); field = "" }
            else if character == "\n", !quoted { row.append(field); rows.append(row); row = []; field = "" }
            else if character != "\r" { field.append(character) }
            index = text.index(after: index)
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}

enum CSVError: Error, Equatable { case invalidEncoding, missingHeader, missingRequiredColumn(String), noValidRows }
