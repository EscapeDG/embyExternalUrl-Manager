import Foundation

// MARK: - JS statement scanner

/// 轻量 JS 语句扫描器：只用于从上游 `constant*.js` 中定位 `const NAME = ...;` 语句，
/// 以便「生成」时保留用户手写的、Manager 没有建模的参数。
/// 识别字符串（' " `）、行注释与块注释；不支持正则字面量（配置文件中不使用）。
enum JSStatementScanner {

    /// 返回 `const|let|var NAME = ... ;` 语句的范围（含结尾分号）。
    static func statementRange(named name: String, in text: String) -> Range<String.Index>? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = "(?m)^[ \\t]*(?:const|let|var)\\s+\(escaped)\\s*="
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: ns),
              let matchRange = Range(match.range, in: text) else { return nil }

        guard let end = scanExpressionEnd(in: text, from: matchRange.upperBound) else { return nil }
        // 语句从关键字起（去掉行首缩进），到分号止
        let startOfKeyword = text[matchRange].firstIndex { !$0.isWhitespace } ?? matchRange.lowerBound
        return startOfKeyword..<end
    }

    static func statement(named name: String, in text: String) -> String? {
        statementRange(named: name, in: text).map { String(text[$0]) }
    }

    /// 从 `from` 起扫描表达式，返回语句结束位置：括号深度为 0 的 `;` 之后；
    /// 若语句省略分号（上游部分配置如此），则在换行且下一个有效字符开启新语句时结束。
    private static func scanExpressionEnd(in text: String, from: String.Index) -> String.Index? {
        var depth = 0
        var index = from
        var lastSigEnd: String.Index?
        var lastSigChar: Character?

        while index < text.endIndex {
            let ch = text[index]
            switch ch {
            case "\"", "'", "`":
                guard let next = skipString(in: text, at: index) else { return nil }
                index = next
                lastSigEnd = next
                lastSigChar = ch
                continue
            case "/":
                let next = text.index(after: index)
                if next < text.endIndex {
                    if text[next] == "/" {
                        index = skipLineComment(in: text, at: index)
                        continue
                    }
                    if text[next] == "*" {
                        guard let after = skipBlockComment(in: text, at: index) else { return nil }
                        index = after
                        continue
                    }
                }
            case "\n":
                if depth == 0, let end = lastSigEnd, let last = lastSigChar,
                   last.isLetter || last.isNumber || "}])\"'`".contains(last),
                   startsNewStatement(in: text, after: index) {
                    return end
                }
                index = text.index(after: index)
                continue
            case "(", "[", "{":
                depth += 1
            case ")", "]", "}":
                depth -= 1
                if depth < 0 { return nil }
            case ";":
                if depth == 0 { return text.index(after: index) }
            default:
                break
            }
            if !ch.isWhitespace {
                lastSigEnd = text.index(after: index)
                lastSigChar = ch
            }
            index = text.index(after: index)
        }
        // 文件结尾且无分号：深度闭合则视为语句结束
        return depth == 0 ? lastSigEnd : nil
    }

    /// 跳过空白与注释后，下一个有效字符是否开启新语句（标识符/EOF），而不是续行运算符。
    private static func startsNewStatement(in text: String, after position: String.Index) -> Bool {
        var index = position
        while index < text.endIndex {
            let ch = text[index]
            if ch.isWhitespace { index = text.index(after: index); continue }
            if ch == "/" {
                let next = text.index(after: index)
                if next < text.endIndex, text[next] == "/" { index = skipLineComment(in: text, at: index); continue }
                if next < text.endIndex, text[next] == "*", let after = skipBlockComment(in: text, at: index) { index = after; continue }
                return false
            }
            return ch.isLetter || ch == "_" || ch == "$"
        }
        return true
    }

    private static func skipString(in text: String, at start: String.Index) -> String.Index? {
        let quote = text[start]
        var index = text.index(after: start)
        while index < text.endIndex {
            let ch = text[index]
            if ch == "\\" {
                index = text.index(index, offsetBy: 2, limitedBy: text.endIndex) ?? text.endIndex
                continue
            }
            if ch == quote { return text.index(after: index) }
            if ch == "\n" && quote != "`" { return nil }
            index = text.index(after: index)
        }
        return nil
    }

    private static func skipLineComment(in text: String, at start: String.Index) -> String.Index {
        var index = start
        while index < text.endIndex, text[index] != "\n" {
            index = text.index(after: index)
        }
        return index
    }

    private static func skipBlockComment(in text: String, at start: String.Index) -> String.Index? {
        guard let close = text.range(of: "*/", range: text.index(start, offsetBy: 2)..<text.endIndex) else { return nil }
        return close.upperBound
    }

    /// 去掉字符串之外的 `//` 与 `/* */` 注释。
    static func stripComments(_ text: String) -> String {
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            let ch = text[index]
            if ch == "\"" || ch == "'" || ch == "`" {
                if let next = skipString(in: text, at: index) {
                    result += text[index..<next]
                    index = next
                    continue
                }
            }
            if ch == "/" {
                let next = text.index(after: index)
                if next < text.endIndex, text[next] == "/" {
                    index = skipLineComment(in: text, at: index)
                    continue
                }
                if next < text.endIndex, text[next] == "*", let after = skipBlockComment(in: text, at: index) {
                    index = after
                    continue
                }
            }
            result.append(ch)
            index = text.index(after: index)
        }
        return result
    }

    /// 取语句右侧第一个 `[ ... ]` 数组的顶层元素（已去注释、去空白、去空元素）。
    static func topLevelArrayElements(ofStatement statement: String) -> [String]? {
        let clean = stripComments(statement)
        guard let eq = clean.firstIndex(of: "="),
              let open = clean[eq...].firstIndex(of: "[") else { return nil }

        var depth = 0
        var elements: [String] = []
        var current = ""
        var index = clean.index(after: open)
        while index < clean.endIndex {
            let ch = clean[index]
            if ch == "\"" || ch == "'" || ch == "`" {
                guard let next = skipString(in: clean, at: index) else { return nil }
                current += clean[index..<next]
                index = next
                continue
            }
            if depth == 0 && ch == "]" {
                let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !tail.isEmpty { elements.append(tail) }
                return elements
            }
            if depth == 0 && ch == "," {
                let item = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !item.isEmpty { elements.append(item) }
                current = ""
                index = clean.index(after: index)
                continue
            }
            if "([{".contains(ch) { depth += 1 }
            if ")]}".contains(ch) { depth -= 1 }
            current.append(ch)
            index = clean.index(after: index)
        }
        return nil
    }
}

// MARK: - Preserve user parameters across generation

/// 生成配置文件时，保留用户在现有文件中手写、而 Manager 没有建模的参数。
enum ConfigPreserver {

    struct Rule {
        /// 整条语句原样保留（用户拥有）。
        var keep: [String] = []
        /// 语句原样保留，仅把 `enable: true|false` 更新为新渲染出的值（Manager 只拥有 enable）。
        var patchEnable: [String] = []
    }

    /// 以模板文件名为键的保留规则。
    static let rules: [String: Rule] = [
        "constant-mount.js": Rule(keep: ["clientSelfAlistRule"]),
        "constant-pro.js": Rule(keep: ["routeRule", "alistRawUrlMapping"], patchEnable: ["routeCacheConfig"]),
        "constant-transcode.js": Rule(patchEnable: ["transcodeConfig"]),
        "constant-ext.js": Rule(keep: [
            "imageCachePolicy", "embyNotificationsAdmin", "embyRedirectSendMessage",
            "itemHiddenRule", "streamConfig", "searchConfig", "playbackInfoConfig"
        ])
    ]

    /// 把 `existing` 中的用户参数合并进刚渲染出的 `rendered`。返回合并结果和被保留的语句名。
    static func merge(
        rendered: String,
        existing: String,
        templateName: String
    ) -> (content: String, preserved: [String], enableChanges: [String]) {
        guard let rule = rules[templateName] else { return (rendered, [], []) }
        var content = rendered
        var preserved: [String] = []
        var enableChanges: [String] = []

        for name in rule.keep {
            guard let old = JSStatementScanner.statement(named: name, in: existing),
                  let range = JSStatementScanner.statementRange(named: name, in: content) else { continue }
            if content[range] != old {
                let customized = normalized(String(content[range])) != normalized(old)
                content.replaceSubrange(range, with: old)
                if customized { preserved.append(name) }
            }
        }

        for name in rule.patchEnable {
            guard let old = JSStatementScanner.statement(named: name, in: existing),
                  let range = JSStatementScanner.statementRange(named: name, in: content),
                  let newValue = enableValue(in: String(content[range])),
                  let patched = replacingEnable(in: old, with: newValue) else { continue }
            if let oldValue = enableValue(in: old), oldValue != newValue {
                enableChanges.append("\(name) 的 enable 由 \(oldValue) 改为 \(newValue)")
            }
            if content[range] != patched {
                let customized = normalized(String(content[range])) != normalized(patched)
                content.replaceSubrange(range, with: patched)
                if customized { preserved.append(name) }
            }
        }
        return (content, preserved, enableChanges)
    }

    /// `mediaPathMapping` 中 Manager 只拥有 `[0, 0, "本地", "远端"]` 形式的条目；
    /// 其余格式（如 `[1, 1, ...]`、带函数的规则）视为用户手写，原样保留。
    static func foreignPathMappingElements(in existing: String) -> [String] {
        guard let statement = JSStatementScanner.statement(named: "mediaPathMapping", in: existing),
              let elements = JSStatementScanner.topLevelArrayElements(ofStatement: statement) else { return [] }
        let managed = #"^\[\s*0\s*,\s*0\s*,\s*"(?:[^"\\]|\\.)*"\s*,\s*"(?:[^"\\]|\\.)*"\s*\]$"#
        guard let regex = try? NSRegularExpression(pattern: managed) else { return [] }
        return elements.filter { element in
            let range = NSRange(element.startIndex..., in: element)
            return regex.firstMatch(in: element, range: range) == nil
        }
    }

    /// 去注释、空白、结尾分号与尾随逗号后的形态，用来判断用户是否真的改过（上游默认值不算）。
    private static func normalized(_ statement: String) -> String {
        var text = JSStatementScanner.stripComments(statement).filter { !$0.isWhitespace }
        if text.hasSuffix(";") { text.removeLast() }
        return text.replacingOccurrences(of: ",]", with: "]").replacingOccurrences(of: ",}", with: "}")
    }

    // MARK: - enable patching

    private static let enablePattern = #"\benable\s*:\s*(true|false)"#

    private static func enableValue(in statement: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: enablePattern),
              let match = regex.firstMatch(in: statement, range: NSRange(statement.startIndex..., in: statement)),
              let range = Range(match.range(at: 1), in: statement) else { return nil }
        return String(statement[range])
    }

    private static func replacingEnable(in statement: String, with value: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: enablePattern),
              let match = regex.firstMatch(in: statement, range: NSRange(statement.startIndex..., in: statement)),
              let range = Range(match.range(at: 1), in: statement) else { return nil }
        var result = statement
        result.replaceSubrange(range, with: value)
        return result
    }
}
