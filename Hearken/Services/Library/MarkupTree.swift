import Foundation

/// A small XML tree, for the files inside an EPUB (container.xml, the package, the table of
/// contents and the XHTML chapters). Element and attribute names are lowercased local names
/// ("dc:title" → "title", "epub:type" → "type").
nonisolated final class MarkupElement: @unchecked Sendable {
    enum Child {
        case element(MarkupElement)
        case text(String)
    }

    let name: String
    let attributes: [String: String]
    fileprivate(set) var children: [Child] = []

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    var elements: [MarkupElement] {
        children.compactMap { if case .element(let e) = $0 { e } else { nil } }
    }

    /// Every descendant element named `name`, in document order.
    func all(_ name: String) -> [MarkupElement] {
        var found: [MarkupElement] = []
        for child in elements {
            if child.name == name { found.append(child) }
            found += child.all(name)
        }
        return found
    }

    func first(_ name: String) -> MarkupElement? {
        for child in elements {
            if child.name == name { return child }
            if let deeper = child.first(name) { return deeper }
        }
        return nil
    }

    subscript(attribute: String) -> String? { attributes[attribute] }

    /// All the text inside, with whitespace collapsed.
    var text: String {
        var out = ""
        func walk(_ element: MarkupElement) {
            for child in element.children {
                switch child {
                case .text(let s): out += s
                case .element(let e): walk(e)
                }
            }
        }
        walk(self)
        return MarkupText.collapse(out)
    }
}

/// Parses XML (and well-formed XHTML) into a MarkupElement tree.
nonisolated enum MarkupParser {
    static func parse(_ data: Data) -> MarkupElement? {
        let source = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        return parse(source)
    }

    static func parse(_ source: String) -> MarkupElement? {
        // XMLParser only knows XML's five named entities; XHTML often uses HTML's.
        let prepared = MarkupText.numericEntities(in: source)
        guard let data = prepared.data(using: .utf8) else { return nil }
        let builder = TreeBuilder()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = builder
        guard parser.parse() || builder.root?.children.isEmpty == false else { return nil }
        return builder.root
    }

    nonisolated private final class TreeBuilder: NSObject, XMLParserDelegate {
        var root: MarkupElement?
        private var stack: [MarkupElement] = []

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            var attrs: [String: String] = [:]
            for (key, value) in attributes {
                let local = key.split(separator: ":").last.map(String.init) ?? key
                attrs[local.lowercased()] = value
                attrs[key.lowercased()] = value
            }
            let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
            let element = MarkupElement(name: local.lowercased(), attributes: attrs)
            if let parent = stack.last {
                parent.children.append(.element(element))
            } else {
                root = element
            }
            stack.append(element)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
            _ = stack.popLast()
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.children.append(.text(string))
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            if let string = String(data: CDATABlock, encoding: .utf8) {
                stack.last?.children.append(.text(string))
            }
        }
    }
}

/// Turns XHTML into reading paragraphs.
nonisolated enum MarkupText {
    /// Elements that start and end a paragraph.
    private static let blocks: Set<String> = [
        "p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "li", "blockquote", "pre", "tr", "dt", "dd",
        "section", "article", "aside", "header", "footer", "figcaption", "table", "ul", "ol", "dl",
        "hr", "address", "center", "body",
    ]
    private static let skipped: Set<String> = ["head", "script", "style", "title", "svg", "math", "noscript", "rt", "rp"]
    static let headings: Set<String> = ["h1", "h2", "h3", "h4"]
    /// Stands in for a line break (from <br>) while whitespace is collapsed.
    private static let lineBreak: Character = "\u{E000}"

    /// The paragraphs of an XHTML document, its first heading, and the paragraph index where
    /// each element whose id is in `anchors` begins (for tables of contents that point into a file).
    static func paragraphs(in root: MarkupElement, anchors: Set<String> = []) -> (paragraphs: [String], heading: String?, markers: [String: Int]) {
        var paragraphs: [String] = []
        var heading: String?
        var markers: [String: Int] = [:]
        var current = ""

        func flush() {
            let text = clean(current)
            if !text.isEmpty { paragraphs.append(text) }
            current = ""
        }

        func walk(_ element: MarkupElement) {
            for child in element.children {
                switch child {
                case .text(let s):
                    current += s
                case .element(let e):
                    if skipped.contains(e.name) { continue }
                    if !anchors.isEmpty, let id = e["id"], anchors.contains(id), markers[id] == nil {
                        // A block starts a new paragraph; an inline anchor belongs to the one in progress.
                        markers[id] = paragraphs.count + (blocks.contains(e.name) && !clean(current).isEmpty ? 1 : 0)
                    }
                    if e.name == "br" {
                        current.append(lineBreak)
                    } else if e.name == "img" {
                        if let alt = e["alt"], !alt.trimmingCharacters(in: .whitespaces).isEmpty, alt.count > 3 {
                            current += " " + alt + " "
                        }
                    } else if blocks.contains(e.name) {
                        flush()
                        let before = paragraphs.count
                        walk(e)
                        flush()
                        if heading == nil, headings.contains(e.name), paragraphs.count > before {
                            heading = paragraphs[before]
                        }
                    } else {
                        walk(e)
                    }
                }
            }
        }

        walk(root.first("body") ?? root)
        flush()
        return (paragraphs, heading, markers)
    }

    /// For markup XMLParser can't read: block tags become paragraph breaks, other tags go.
    static func paragraphs(inBrokenMarkup source: String) -> [String] {
        var text = source
        for pattern in [#"(?is)<(head|script|style)\b.*?</\1>"#, #"(?s)<!--.*?-->"#] {
            text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        text = text.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: String(lineBreak), options: .regularExpression)
        text = text.replacingOccurrences(
            of: #"(?i)</?(p|div|h[1-6]|li|blockquote|pre|tr|section|article|table|ul|ol|hr)\b[^>]*>"#,
            with: "\u{E001}", options: .regularExpression
        )
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        text = decodeEntities(text)
        return text.split(separator: "\u{E001}").map { clean(String($0)) }.filter { !$0.isEmpty }
    }

    /// Collapses whitespace and restores line breaks.
    static func clean(_ text: String) -> String {
        collapse(text)
            .replacingOccurrences(of: " \(lineBreak)", with: String(lineBreak))
            .replacingOccurrences(of: "\(lineBreak) ", with: String(lineBreak))
            .split(separator: lineBreak, omittingEmptySubsequences: true)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Runs of spaces, tabs, newlines and no-break spaces become one space.
    static func collapse(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        var pendingSpace = false
        for character in text {
            if character == " " || character == "\n" || character == "\t" || character == "\r" || character == "\u{00A0}" || character == "\r\n" {
                pendingSpace = true
            } else {
                if pendingSpace && !out.isEmpty { out.append(" ") }
                pendingSpace = false
                out.append(character)
            }
        }
        return out
    }

    private static let named: [String: String] = [
        "nbsp": "#160", "mdash": "#8212", "ndash": "#8211", "lsquo": "#8216", "rsquo": "#8217",
        "ldquo": "#8220", "rdquo": "#8221", "hellip": "#8230", "copy": "#169", "reg": "#174",
        "trade": "#8482", "shy": "#173", "middot": "#183", "bull": "#8226", "para": "#182",
        "sect": "#167", "deg": "#176", "laquo": "#171", "raquo": "#187", "thinsp": "#8201",
        "ensp": "#8194", "emsp": "#8195", "zwnj": "#8204", "zwj": "#8205", "dagger": "#8224",
        "Dagger": "#8225", "prime": "#8242", "Prime": "#8243", "frac12": "#189", "frac14": "#188",
        "frac34": "#190", "times": "#215", "divide": "#247", "aelig": "#230", "AElig": "#198",
        "oelig": "#339", "OElig": "#338", "eacute": "#233", "Eacute": "#201", "egrave": "#232",
        "ecirc": "#234", "euml": "#235", "aacute": "#225", "agrave": "#224", "acirc": "#226",
        "auml": "#228", "iacute": "#237", "icirc": "#238", "iuml": "#239", "oacute": "#243",
        "ocirc": "#244", "ouml": "#246", "uacute": "#250", "ucirc": "#251", "uuml": "#252",
        "ccedil": "#231", "ntilde": "#241", "szlig": "#223", "aring": "#229", "oslash": "#248",
    ]

    /// Rewrites HTML's named entities (&nbsp;) as numeric ones (&#160;), leaving XML's own five.
    static func numericEntities(in source: String) -> String {
        guard source.contains("&") else { return source }
        let pattern = #/&([A-Za-z][A-Za-z0-9]{1,8});/#
        return source.replacing(pattern) { match in
            let name = String(match.1)
            if ["amp", "lt", "gt", "quot", "apos"].contains(name) { return "&\(name);" }
            if let code = named[name] { return "&\(code);" }
            return " "
        }
    }

    /// Decodes entities in plain text (the fallback path).
    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = numericEntities(in: text)
        result = result.replacing(#/&#(x?)([0-9A-Fa-f]+);/#) { match in
            let value = match.1.isEmpty ? UInt32(match.2) : UInt32(match.2, radix: 16)
            return value.flatMap { Unicode.Scalar($0) }.map { String(Character($0)) } ?? ""
        }
        return result
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
