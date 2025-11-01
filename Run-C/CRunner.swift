import Foundation
import os

// MARK: - Unified Logging

enum LogCategory: String {
    case general = "general"
    case compiler = "compiler"
    case ui = "ui"
    case editor = "editor"
}

enum LogLevel: String { case debug = "DEBUG", info = "INFO", warn = "WARN", error = "ERROR" }

final class Log {
    static let shared = Log()

    private let subsystem: String
    private let fileQueue = DispatchQueue(label: "run-c.logger.file", qos: .utility)
    private var fileHandle: FileHandle?
    private var currentLogURL: URL?
    private let maxFileBytes: Int = 512 * 1024 // 512 KB per file
    private let maxFiles = 5

    private init() {
        self.subsystem = Bundle.main.bundleIdentifier ?? "Run-C"
        prepareFileLogging()
    }

    // Public API
    static func debug(_ message: @autoclosure () -> String,
                      category: LogCategory = .general,
                      file: StaticString = #fileID,
                      function: StaticString = #function,
                      line: UInt = #line) {
        shared.write(level: .debug, category: category, message: message(), file: String(describing: file), function: String(describing: function), line: line)
    }

    static func info(_ message: @autoclosure () -> String,
                     category: LogCategory = .general,
                     file: StaticString = #fileID,
                     function: StaticString = #function,
                     line: UInt = #line) {
        shared.write(level: .info, category: category, message: message(), file: String(describing: file), function: String(describing: function), line: line)
    }

    static func warn(_ message: @autoclosure () -> String,
                     category: LogCategory = .general,
                     file: StaticString = #fileID,
                     function: StaticString = #function,
                     line: UInt = #line) {
        shared.write(level: .warn, category: category, message: message(), file: String(describing: file), function: String(describing: function), line: line)
    }

    static func error(_ message: @autoclosure () -> String,
                      category: LogCategory = .general,
                      file: StaticString = #fileID,
                      function: StaticString = #function,
                      line: UInt = #line) {
        shared.write(level: .error, category: category, message: message(), file: String(describing: file), function: String(describing: function), line: line)
    }

    static func logFileURLs() -> [URL] {
        shared.listLogFiles()
    }

    // Internal
    private func write(level: LogLevel, category: LogCategory, message: String, file: String, function: String, line: UInt) {
        let logger = os.Logger(subsystem: subsystem, category: category.rawValue)
        switch level {
        case .debug: logger.debug("\(message, privacy: .public)")
        case .info: logger.info("\(message, privacy: .public)")
        case .warn: logger.warning("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        }

        // File
        fileQueue.async { [weak self] in
            guard let self = self else { return }
            let ts = ISO8601DateFormatter().string(from: Date())
            let lineText = "[\(level.rawValue)] [\(category.rawValue)] [\(ts)] \(message) (\(file):\(line) \(function))\n"
            self.appendToFile(lineText)
        }
    }

    private func logsDirectory() -> URL? {
        do {
            let dir = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Logs", isDirectory: true)
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            return dir
        } catch {
            return nil
        }
    }

    private func prepareFileLogging() {
        fileQueue.sync {
            guard let dir = logsDirectory() else { return }
            let date = Date()
            let df = DateFormatter()
            df.dateFormat = "yyyyMMdd"
            let filename = "run-c-\(df.string(from: date)).log"
            let url = dir.appendingPathComponent(filename)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            currentLogURL = url
            fileHandle = try? FileHandle(forWritingTo: url)
            try? fileHandle?.seekToEnd()
            rotateIfNeeded()
        }
    }

    private func appendToFile(_ text: String) {
        guard let handle = fileHandle, let data = text.data(using: .utf8) else { return }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            rotateIfNeeded()
        } catch {
            // If writing fails, try to reopen once
            prepareFileLogging()
        }
    }

    private func rotateIfNeeded() {
        guard let url = currentLogURL else { return }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path), let size = attrs[.size] as? NSNumber else { return }
        if size.intValue < maxFileBytes { return }

        // Close current
        try? fileHandle?.close()
        fileHandle = nil

        // Rename with timestamp
        let ts = Int(Date().timeIntervalSince1970)
        let rotated = url.deletingPathExtension().appendingPathExtension("\(ts).log")
        try? FileManager.default.moveItem(at: url, to: rotated)

        // Cleanup old
        cleanupOldLogs()

        // Start a new
        prepareFileLogging()
    }

    private func listLogFiles() -> [URL] {
        guard let dir = logsDirectory() else { return [] }
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        return urls.sorted { (a, b) -> Bool in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da ?? .distantPast > db ?? .distantPast
        }
    }

    private func cleanupOldLogs() {
        let urls = listLogFiles()
        if urls.count <= maxFiles { return }
        for url in urls.suffix(from: maxFiles) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

/// Result returned by the offline runner.
struct CExecutionResult {
    let output: String
    let warnings: [String]
    let duration: TimeInterval
}

/// Domain errors that can be raised when compiling/executing code.
enum CCompilerError: LocalizedError {
    case syntax(message: String, lineNumber: Int?)
    case runtime(message: String, lineNumber: Int?)
    case unsupported(message: String)
    case internalError(message: String)

    var errorDescription: String? {
        switch self {
        case .syntax(let message, let lineNumber):
            let lineText = lineNumber.map { " on line \($0)" } ?? ""
            return "Syntax error\(lineText): \(message)"
        case .runtime(let message, let lineNumber):
            let lineText = lineNumber.map { " on line \($0)" } ?? ""
            return "Runtime error\(lineText): \(message)"
        case .unsupported(let message):
            return "Unsupported feature: \(message)"
        case .internalError(let message):
            return "Internal error: \(message)"
        }
    }
}

/// Public entry point used by the SwiftUI layer.
final class OfflineCCompiler {
    func run(source: String) -> Result<CExecutionResult, CCompilerError> {
        let startedAt = Date()
        Log.info("Run started (chars=\(source.count))", category: .compiler)
        do {
            let sanitized = preprocess(source: source)
            Log.debug("Preprocessed source length=\(sanitized.count)", category: .compiler)
            var lexer = CLexer(source: sanitized)
            let tokens = try lexer.tokenize()
            Log.debug("Tokenized count=\(tokens.count) line=\(lexer.lineNumber)", category: .compiler)
            var parser = CParser(tokens: tokens)
            let statements = try parser.parseProgram()
            Log.debug("Parsed statements=\(statements.count) warnings=\(parser.warnings.count)", category: .compiler)
            var interpreter = CInterpreter()
            let stdout = try interpreter.execute(statements: statements)
            Log.debug("Interpreter warnings=\(interpreter.warnings.count) outputLength=\(stdout.count)", category: .compiler)
            let warnings = parser.warnings + interpreter.warnings
            let duration = Date().timeIntervalSince(startedAt)
            Log.info("Run finished success in \(String(format: "%.3f", duration))s (warnings=\(warnings.count))", category: .compiler)
            return .success(CExecutionResult(output: stdout, warnings: warnings, duration: duration))
        } catch let error as CCompilerError {
            Log.error("Run failed: \(error.localizedDescription)", category: .compiler)
            return .failure(error)
        } catch {
            Log.error("Run failed (internal): \(error.localizedDescription)", category: .compiler)
            return .failure(.internalError(message: error.localizedDescription))
        }
    }

    private func preprocess(source: String) -> String {
        source
            .replacingOccurrences(of: "\r\n", with: "\n")
            // Normalize curly quotes and dashes that iOS keyboards may insert
            .replacingOccurrences(of: "\u{201C}", with: "\"") // “
            .replacingOccurrences(of: "\u{201D}", with: "\"") // ”
            .replacingOccurrences(of: "\u{2018}", with: "'")   // ‘
            .replacingOccurrences(of: "\u{2019}", with: "'")   // ’
            .replacingOccurrences(of: "\u{2013}", with: "-")   // –
            .replacingOccurrences(of: "\u{2014}", with: "-")   // —
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
            .joined(separator: "\n")
    }
}

// MARK: - Lexer

private enum Token: Equatable {
    case keyword(String, lineNumber: Int)
    case identifier(String, lineNumber: Int)
    case number(Int, lineNumber: Int)
    case stringLiteral(String, lineNumber: Int)
    case symbol(String, lineNumber: Int)
}

private struct CLexer {
    private let characters: [Character]
    private var index: Int = 0
    private(set) var lineNumber: Int = 1

    private static let keywords: Set<String> = [
        // control/flow
        "return", "if", "else", "while", "for", "break", "continue",
        // primitive types (treated as 'int' by the interpreter)
        "int", "long", "char", "void"
    ]

    private static let compoundSymbols: [String] = [
        "<=", ">=", "==", "!=", "&&", "||", "++", "--",
        "+=", "-=", "*=", "/=", "%="
    ]

    init(source: String) {
        self.characters = Array(source)
    }

    mutating func tokenize() throws -> [Token] {
        var tokens: [Token] = []

        while let current = peek() {
            if current.isWhitespace {
                _ = advance()
                continue
            }

            if current == "/" && peek(aheadBy: 1) == "/" {
                skipLine()
                continue
            }

            if current == "/" && peek(aheadBy: 1) == "*" {
                try skipBlockComment()
                continue
            }

            if current.isNumber {
                tokens.append(readNumber())
                continue
            }

            if current.isLetter || current == "_" {
                tokens.append(readIdentifier())
                continue
            }

            if current == "\"" {
                tokens.append(try readStringLiteral())
                continue
            }

            if let token = readSymbol() {
                tokens.append(token)
                continue
            }

            throw CCompilerError.syntax(message: "Unexpected character '\(current)'", lineNumber: lineNumber)
        }

        return tokens
    }

    private mutating func readNumber() -> Token {
        let startLine = lineNumber
        var value = ""
        while let current = peek(), current.isNumber {
            value.append(current)
            _ = advance()
        }
        return .number(Int(value) ?? 0, lineNumber: startLine)
    }

    private mutating func readIdentifier() -> Token {
        let startLine = lineNumber
        var value = ""
        while let current = peek(), current.isLetter || current.isNumber || current == "_" {
            value.append(current)
            _ = advance()
        }
        if CLexer.keywords.contains(value) {
            return .keyword(value, lineNumber: startLine)
        } else {
            return .identifier(value, lineNumber: startLine)
        }
    }

    private mutating func readStringLiteral() throws -> Token {
        let startLine = lineNumber
        _ = advance() // Opening quote
        var buffer = ""
        while let current = peek() {
            if current == "\"" {
                _ = advance()
                return .stringLiteral(buffer, lineNumber: startLine)
            }

            if current == "\\" {
                _ = advance()
                guard let escaped = peek() else { break }
                let mapped: Character
                switch escaped {
                case "n": mapped = "\n"
                case "t": mapped = "\t"
                case "r": mapped = "\r"
                case "\"": mapped = "\""
                case "\\": mapped = "\\"
                default: mapped = escaped
                }
                buffer.append(mapped)
                _ = advance()
                continue
            }

            buffer.append(current)
            _ = advance()
        }
        throw CCompilerError.syntax(message: "Unterminated string literal", lineNumber: lineNumber)
    }

    private mutating func readSymbol() -> Token? {
        let startLine = lineNumber
        if let compound = CLexer.compoundSymbols.first(where: matches(symbol:)) {
            index += compound.count
            return .symbol(compound, lineNumber: startLine)
        }

        guard let char = advance() else { return nil }
        return .symbol(String(char), lineNumber: startLine)
    }

    private func matches(symbol: String) -> Bool {
        guard index + symbol.count <= characters.count else { return false }
        let slice = characters[index..<(index + symbol.count)]
        return String(slice) == symbol
    }

    private mutating func skipLine() {
        while let current = peek(), current != "\n" {
            _ = advance()
        }
        _ = advance()
    }

    private mutating func skipBlockComment() throws {
        _ = advance()
        _ = advance()
        while index < characters.count - 1 {
            if characters[index] == "*" && characters[index + 1] == "/" {
                index += 2
                return
            }
            index += 1
        }
        throw CCompilerError.syntax(message: "Unterminated block comment", lineNumber: lineNumber)
    }

    private func peek(aheadBy offset: Int = 0) -> Character? {
        let target = index + offset
        guard characters.indices.contains(target) else { return nil }
        return characters[target]
    }

    @discardableResult
    private mutating func advance() -> Character? {
        guard index < characters.count else { return nil }
        let char = characters[index]
        index += 1
        if char == "\n" {
            lineNumber += 1
        }
        return char
    }
}

// MARK: - Parser

private indirect enum Statement {
    case declaration(name: String, value: Expression?)
    case assignment(name: String, op: AssignmentOperator, value: Expression)
    case printf(format: String, arguments: [Expression])
    case ifStatement(condition: Expression, thenBlock: [Statement], elseBlock: [Statement]?)
    case whileLoop(condition: Expression, body: [Statement])
    case forLoop(initializer: Statement?, condition: Expression?, increment: Statement?, body: [Statement])
    case returnStatement(Expression?)
    case block([Statement])
    case empty
}

private enum AssignmentOperator {
    case assign
    case add
    case subtract
    case multiply
    case divide
    case mod
}

private indirect enum Expression {
    case number(Int)
    case identifier(String)
    case unary(op: UnaryOperator, Expression)
    case binary(lhs: Expression, op: BinaryOperator, rhs: Expression)
}

private enum UnaryOperator {
    case positive
    case negative
    case logicalNot
}

private enum BinaryOperator {
    case multiply, divide, mod
    case add, subtract
    case lessThan, lessThanOrEqual, greaterThan, greaterThanOrEqual
    case equal, notEqual
    case logicalAnd, logicalOr
}

private struct CParser {
    private let tokens: [Token]
    private var index: Int = 0
    private(set) var warnings: [String] = []

    init(tokens: [Token]) {
        self.tokens = tokens
    }

    mutating func parseProgram() throws -> [Statement] {
        _ = consumeNewlines()
        // Be tolerant: scan forward to find 'int|long|char void? main'
        var scanIndex = index
        while scanIndex < tokens.count {
            let tok = tokens[scanIndex]
            if case .keyword(let kw, _) = tok, ["int","long","char"].contains(kw) {
                if scanIndex + 1 < tokens.count,
                   case .identifier("main", _) = tokens[scanIndex + 1] {
                    index = scanIndex
                    break
                }
            }
            scanIndex += 1
        }
        guard match(keyword: "int") || match(keyword: "long") || match(keyword: "char") else {
            throw CCompilerError.syntax(message: "Program must define int main() (only a small C subset is supported)", lineNumber: currentLineNumber)
        }
        guard case .identifier("main", _)? = advance() else {
            throw CCompilerError.syntax(message: "Expected 'main' function", lineNumber: currentLineNumber)
        }
        try consumeParameterList()
        return try parseBlock()
    }

    private mutating func consumeParameterList() throws {
        guard match(symbol: "(") else {
            throw CCompilerError.syntax(message: "Expected '(' after main", lineNumber: currentLineNumber)
        }
        var depth = 1
        while depth > 0 {
            guard let token = advance() else {
                throw CCompilerError.syntax(message: "Unterminated parameter list", lineNumber: currentLineNumber)
            }
            if case .symbol("(", _) = token {
                depth += 1
            } else if case .symbol(")", _) = token {
                depth -= 1
            }
        }
    }

    private mutating func parseBlock() throws -> [Statement] {
        guard match(symbol: "{") else {
            throw CCompilerError.syntax(message: "Expected '{' to start block", lineNumber: currentLineNumber)
        }
        var statements: [Statement] = []
        while !check(symbol: "}") {
            if isAtEnd {
                throw CCompilerError.syntax(message: "Unterminated block", lineNumber: currentLineNumber)
            }
            statements.append(try parseStatement())
        }
        _ = advance()
        return statements
    }

    private mutating func parseStatement() throws -> Statement {
        if check(symbol: "{") {
            return .block(try parseBlock())
        }

        if let decl = try parseTypeDeclarationIfPresent() { return decl }

        if match(keyword: "return") {
            if match(symbol: ";") {
                return .returnStatement(nil)
            }
            let expr = try parseExpression()
            try consume(symbol: ";")
            return .returnStatement(expr)
        }

        if match(keyword: "if") {
            return try parseIfStatement()
        }

        if match(keyword: "while") {
            return try parseWhileStatement()
        }

        if match(keyword: "for") {
            return try parseForStatement()
        }

        if case .identifier("printf", _)? = peek() {
            _ = advance()
            return try parsePrintfCall()
        }

        if match(symbol: ";") {
            return .empty
        }

        return try parseAssignmentLikeStatement()
    }

    private mutating func parseTypeDeclarationIfPresent(expectTerminator: Bool = true) throws -> Statement? {
        // Accept int/long/char as equivalent scalar type
        let supportedTypes = ["int","long","char"]
        var matchedType: String?
        for t in supportedTypes {
            if match(keyword: t) { matchedType = t; break }
        }
        guard matchedType != nil else { return nil }

        var decls: [Statement] = []
        // At least one declarator
        repeat {
            guard case .identifier(let name, _)? = advance() else {
                throw CCompilerError.syntax(message: "Expected identifier after type", lineNumber: currentLineNumber)
            }
            var initialValue: Expression?
            if match(symbol: "=") {
                initialValue = try parseExpression()
            }
            decls.append(.declaration(name: name, value: initialValue))
        } while match(symbol: ",")

        if expectTerminator {
            try consume(symbol: ";")
        }
        return decls.count == 1 ? decls[0] : .block(decls)
    }

    private mutating func parseAssignmentLikeStatement(expectTerminator: Bool = true) throws -> Statement {
        guard case .identifier(let name, _)? = advance() else {
            throw CCompilerError.syntax(message: "Expected identifier", lineNumber: currentLineNumber)
        }

        if match(symbol: "++") {
            if expectTerminator { try consume(symbol: ";") }
            let increment = Expression.binary(lhs: .identifier(name), op: .add, rhs: .number(1))
            return .assignment(name: name, op: .assign, value: increment)
        }

        if match(symbol: "--") {
            if expectTerminator { try consume(symbol: ";") }
            let decrement = Expression.binary(lhs: .identifier(name), op: .subtract, rhs: .number(1))
            return .assignment(name: name, op: .assign, value: decrement)
        }

        guard case .symbol(let symbol, _)? = advance() else {
            throw CCompilerError.syntax(message: "Expected assignment operator after identifier '\(name)'", lineNumber: currentLineNumber)
        }

        let assignmentOperator: AssignmentOperator
        switch symbol {
        case "=": assignmentOperator = .assign
        case "+=": assignmentOperator = .add
        case "-=": assignmentOperator = .subtract
        case "*=": assignmentOperator = .multiply
        case "/=": assignmentOperator = .divide
        case "%=": assignmentOperator = .mod
        default:
            throw CCompilerError.unsupported(message: "Operator '\(symbol)'")
        }

        let expression = try parseExpression()
        if expectTerminator {
            try consume(symbol: ";")
        }

        return .assignment(name: name, op: assignmentOperator, value: expression)
    }

    private mutating func parsePrintfCall() throws -> Statement {
        try consume(symbol: "(")
        guard case .stringLiteral(let format, _)? = advance() else {
            throw CCompilerError.syntax(message: "printf expects a string literal as the first argument", lineNumber: currentLineNumber)
        }
        var arguments: [Expression] = []
        while match(symbol: ",") {
            arguments.append(try parseExpression())
        }
        try consume(symbol: ")")
        try consume(symbol: ";")
        return .printf(format: format, arguments: arguments)
    }

    private mutating func parseIfStatement() throws -> Statement {
        try consume(symbol: "(")
        let condition = try parseExpression()
        try consume(symbol: ")")
        let thenBlock = try parseStatementBody()
        var elseBlock: [Statement]?
        if match(keyword: "else") {
            elseBlock = try parseStatementBody()
        }
        return .ifStatement(condition: condition, thenBlock: thenBlock, elseBlock: elseBlock)
    }

    private mutating func parseWhileStatement() throws -> Statement {
        try consume(symbol: "(")
        let condition = try parseExpression()
        try consume(symbol: ")")
        let body = try parseStatementBody()
        return .whileLoop(condition: condition, body: body)
    }

    private mutating func parseForStatement() throws -> Statement {
        try consume(symbol: "(")
        let initializer = try parseForInitializer()
        try consume(symbol: ";")
        let condition = try parseForExpressionSection()
        try consume(symbol: ";")
        let increment = try parseForIncrement()
        try consume(symbol: ")")
        let body = try parseStatementBody()
        return .forLoop(initializer: initializer, condition: condition, increment: increment, body: body)
    }

    private mutating func parseForInitializer() throws -> Statement? {
        if check(symbol: ";") {
            return nil
        }
        if let decl = try parseTypeDeclarationIfPresent(expectTerminator: false) { return decl }
        return try parseAssignmentLikeStatement(expectTerminator: false)
    }

    private mutating func parseForExpressionSection() throws -> Expression? {
        if check(symbol: ";") {
            return nil
        }
        return try parseExpression()
    }

    private mutating func parseForIncrement() throws -> Statement? {
        if check(symbol: ")") {
            return nil
        }
        if case .identifier? = peek() {
            return try parseAssignmentLikeStatement(expectTerminator: false)
        }
        return nil
    }

    private mutating func parseStatementBody() throws -> [Statement] {
        if check(symbol: "{") {
            return try parseBlock()
        }
        return [try parseStatement()]
    }

    private mutating func parseExpression() throws -> Expression {
        try parseBinaryExpression(minimumPrecedence: 0)
    }

    private func precedence(for op: BinaryOperator) -> Int {
        switch op {
        case .logicalOr: return 1
        case .logicalAnd: return 2
        case .equal, .notEqual: return 3
        case .lessThan, .lessThanOrEqual, .greaterThan, .greaterThanOrEqual: return 4
        case .add, .subtract: return 5
        case .multiply, .divide, .mod: return 6
        }
    }

    private mutating func parseBinaryExpression(minimumPrecedence: Int) throws -> Expression {
        var left = try parseUnaryExpression()

        while let op = currentBinaryOperator(), precedence(for: op) >= minimumPrecedence {
            _ = advance()
            let nextMinPrecedence = precedence(for: op) + 1
            let right = try parseBinaryExpression(minimumPrecedence: nextMinPrecedence)
            left = .binary(lhs: left, op: op, rhs: right)
        }

        return left
    }

    private mutating func parseUnaryExpression() throws -> Expression {
        if match(symbol: "+") {
            let value = try parseUnaryExpression()
            return .unary(op: .positive, value)
        }
        if match(symbol: "-") {
            let value = try parseUnaryExpression()
            return .unary(op: .negative, value)
        }
        if match(symbol: "!") {
            let value = try parseUnaryExpression()
            return .unary(op: .logicalNot, value)
        }
        if match(symbol: "(") {
            let expr = try parseExpression()
            try consume(symbol: ")")
            return expr
        }
        guard let token = advance() else {
            throw CCompilerError.syntax(message: "Unexpected end of expression", lineNumber: currentLineNumber)
        }
        switch token {
        case .number(let value, _):
            return .number(value)
        case .identifier(let name, _):
            return .identifier(name)
        default:
            throw CCompilerError.syntax(message: "Unexpected token in expression", lineNumber: currentLineNumber)
        }
    }

    private func currentBinaryOperator() -> BinaryOperator? {
        guard case .symbol(let symbol, _)? = peek() else { return nil }
        switch symbol {
        case "*": return .multiply
        case "/": return .divide
        case "%": return .mod
        case "+": return .add
        case "-": return .subtract
        case "<": return .lessThan
        case "<=": return .lessThanOrEqual
        case ">": return .greaterThan
        case ">=": return .greaterThanOrEqual
        case "==": return .equal
        case "!=": return .notEqual
        case "&&": return .logicalAnd
        case "||": return .logicalOr
        default:
            return nil
        }
    }

    private func peek(aheadBy offset: Int = 0) -> Token? {
        let target = index + offset
        return tokens.indices.contains(target) ? tokens[target] : nil
    }

    private mutating func advance() -> Token? {
        guard !isAtEnd else { return nil }
        let token = tokens[index]
        index += 1
        return token
    }

    private mutating func consume(symbol: String) throws {
        let line = currentLineNumber
        guard match(symbol: symbol) else {
            throw CCompilerError.syntax(message: "Expected '\(symbol)'", lineNumber: line)
        }
    }

    private mutating func match(symbol: String) -> Bool {
        guard case .symbol(let value, _)? = peek(), value == symbol else { return false }
        _ = advance()
        return true
    }

    private mutating func match(keyword: String) -> Bool {
        guard case .keyword(let value, _)? = peek(), value == keyword else { return false }
        _ = advance()
        return true
    }

    private func check(symbol: String) -> Bool {
        guard case .symbol(let value, _)? = peek() else { return false }
        return value == symbol
    }

    private var currentLineNumber: Int? {
        guard let token = peek() else { return nil }
        switch token {
        case .keyword(_, let line), .identifier(_, let line), .number(_, let line), .stringLiteral(_, let line), .symbol(_, let line):
            return line
        }
    }

    private var isAtEnd: Bool {
        index >= tokens.count
    }

    private mutating func consumeNewlines() -> Int {
        var consumed = 0
        while match(symbol: "\n") {
            consumed += 1
        }
        return consumed
    }
}

// MARK: - Interpreter

private final class ExecutionContext {
    private var scopes: [[String: Int]] = [[:]]

    func pushScope() {
        scopes.append([:])
    }

    func popScope() {
        _ = scopes.popLast()
        if scopes.isEmpty { scopes = [[:]] }
    }

    func declare(_ name: String, value: Int) {
        scopes[scopes.count - 1][name] = value
    }

    func assign(_ name: String, value: Int) throws {
        for index in stride(from: scopes.count - 1, through: 0, by: -1) {
            if scopes[index][name] != nil {
                scopes[index][name] = value
                return
            }
        }
        throw CCompilerError.runtime(message: "Variable '\(name)' used before declaration", lineNumber: nil)
    }

    func value(of name: String) throws -> Int {
        for scope in scopes.reversed() {
            if let value = scope[name] {
                return value
            }
        }
        throw CCompilerError.runtime(message: "Variable '\(name)' used before declaration", lineNumber: nil)
    }
}

private enum ExecutionSignal {
    case none
    case returned(Int)
}

private struct CInterpreter {
    private(set) var warnings: [String] = []
    private var stdout = ""
    private var context = ExecutionContext()

    mutating func execute(statements: [Statement]) throws -> String {
        _ = try runBlock(statements)
        return stdout
    }

    private mutating func runBlock(_ statements: [Statement]) throws -> ExecutionSignal {
        context.pushScope()
        defer { context.popScope() }
        for statement in statements {
            if case .returned(let value) = try execute(statement: statement) {
                return .returned(value)
            }
        }
        return .none
    }

    private mutating func execute(statement: Statement) throws -> ExecutionSignal {
        switch statement {
        case .empty:
            return .none
        case .declaration(let name, let expression):
            let value = expression != nil ? try evaluate(expression!) : 0
            context.declare(name, value: value)
            return .none
        case .assignment(let name, let op, let expression):
            let rhs = try evaluate(expression)
            let newValue: Int
            switch op {
            case .assign:
                newValue = rhs
            case .add:
                newValue = try context.value(of: name) + rhs
            case .subtract:
                newValue = try context.value(of: name) - rhs
            case .multiply:
                newValue = try context.value(of: name) * rhs
            case .divide:
                guard rhs != 0 else { throw CCompilerError.runtime(message: "Division by zero", lineNumber: nil) }
                newValue = try context.value(of: name) / rhs
            case .mod:
                guard rhs != 0 else { throw CCompilerError.runtime(message: "Modulo by zero", lineNumber: nil) }
                newValue = try context.value(of: name) % rhs
            }
            try context.assign(name, value: newValue)
            return .none
        case .block(let statements):
            return try runInlineBlock(statements)
        case .printf(let format, let arguments):
            let values = try arguments.map { try evaluate($0) }
            stdout.append(renderPrintf(format: format, values: values))
            return .none
        case .ifStatement(let condition, let thenBlock, let elseBlock):
            if try evaluate(condition) != 0 {
                return try runInlineBlock(thenBlock)
            } else if let elseBlock {
                return try runInlineBlock(elseBlock)
            }
            return .none
        case .whileLoop(let condition, let body):
            return try executeWhile(condition: condition, body: body)
        case .forLoop(let initializer, let condition, let increment, let body):
            return try executeFor(initializer: initializer, condition: condition, increment: increment, body: body)
        case .returnStatement(let expression):
            let value = try expression.map { try evaluate($0) } ?? 0
            return .returned(value)
        }
    }

    private mutating func runInlineBlock(_ statements: [Statement]) throws -> ExecutionSignal {
        context.pushScope()
        defer { context.popScope() }
        for statement in statements {
            let signal = try execute(statement: statement)
            if case .returned = signal {
                return signal
            }
        }
        return .none
    }

    private mutating func executeWhile(condition: Expression, body: [Statement]) throws -> ExecutionSignal {
        while try evaluate(condition) != 0 {
            let signal = try runInlineBlock(body)
            if case .returned = signal {
                return signal
            }
        }
        return .none
    }

    private mutating func executeFor(initializer: Statement?, condition: Expression?, increment: Statement?, body: [Statement]) throws -> ExecutionSignal {
        context.pushScope()
        if let initializer {
            _ = try execute(statement: initializer)
        }
        while (try condition.map { try evaluate($0) != 0 } ?? true) {
            let signal = try runInlineBlock(body)
            if case .returned = signal {
                context.popScope()
                return signal
            }
            if let increment {
                _ = try execute(statement: increment)
            }
        }
        context.popScope()
        return .none
    }

    private mutating func evaluate(_ expression: Expression) throws -> Int {
        switch expression {
        case .number(let value):
            return value
        case .identifier(let name):
            return try context.value(of: name)
        case .unary(let op, let inner):
            let value = try evaluate(inner)
            switch op {
            case .positive: return value
            case .negative: return -value
            case .logicalNot: return value == 0 ? 1 : 0
            }
        case .binary(let lhs, let op, let rhs):
            let left = try evaluate(lhs)
            let right = try evaluate(rhs)
            switch op {
            case .multiply: return left * right
            case .divide:
                guard right != 0 else { throw CCompilerError.runtime(message: "Division by zero", lineNumber: nil) }
                return left / right
            case .mod:
                guard right != 0 else { throw CCompilerError.runtime(message: "Modulo by zero", lineNumber: nil) }
                return left % right
            case .add: return left + right
            case .subtract: return left - right
            case .lessThan: return left < right ? 1 : 0
            case .lessThanOrEqual: return left <= right ? 1 : 0
            case .greaterThan: return left > right ? 1 : 0
            case .greaterThanOrEqual: return left >= right ? 1 : 0
            case .equal: return left == right ? 1 : 0
            case .notEqual: return left != right ? 1 : 0
            case .logicalAnd: return (left != 0 && right != 0) ? 1 : 0
            case .logicalOr: return (left != 0 || right != 0) ? 1 : 0
            }
        }
    }

    private mutating func renderPrintf(format: String, values: [Int]) -> String {
        var buffer = ""
        var valueIndex = 0
        var index = format.startIndex
        let allowedSpecifiers: Set<Character> = ["d", "i", "u", "x", "X", "c"]
        while index < format.endIndex {
            let char = format[index]
            if char == "%" {
                let nextIndex = format.index(after: index)
                if nextIndex < format.endIndex {
                    let specifier = format[nextIndex]
                    if specifier == "%" {
                        buffer.append("%")
                        index = format.index(after: nextIndex)
                        continue
                    }
                    if allowedSpecifiers.contains(specifier) {
                        if valueIndex < values.count {
                            let value = values[valueIndex]
                            switch specifier {
                            case "x":
                                buffer.append(String(format: "%x", value))
                            case "X":
                                buffer.append(String(format: "%X", value))
                            case "u":
                                let unsignedValue = UInt32(bitPattern: Int32(value))
                                buffer.append(String(unsignedValue))
                            case "c":
                                if let scalar = UnicodeScalar(value & 0xFF) {
                                    buffer.append(Character(scalar))
                                } else {
                                    warnings.append("Value \(value) cannot be represented as a character")
                                }
                            default:
                                buffer.append(String(value))
                            }
                            valueIndex += 1
                            index = format.index(after: nextIndex)
                            continue
                        } else {
                            warnings.append("printf expected more values for format specifier '%\(specifier)'")
                        }
                    }
                }
            }
            buffer.append(char)
            index = format.index(after: index)
        }
        if valueIndex < values.count {
            warnings.append("printf received \(values.count) values but only consumed \(valueIndex)")
        }
        return buffer
    }
}
