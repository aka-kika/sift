import Foundation

/// Builds RFC-4180 CSV text. Pure and testable — no app types, no I/O.
enum CSVExporter {

    /// Quotes a single field per RFC-4180: fields containing a comma, double quote,
    /// CR or LF are wrapped in double quotes, with embedded quotes doubled.
    static func field(_ value: String) -> String {
        let needsQuoting = value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" })
        guard needsQuoting else { return value }
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    /// Joins a header and rows into CSV text using CRLF line endings (RFC-4180).
    static func make(header: [String], rows: [[String]]) -> String {
        var lines: [String] = []
        lines.append(header.map(field).joined(separator: ","))
        for row in rows {
            lines.append(row.map(field).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }
}
