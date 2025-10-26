import Foundation

/// Result returned by the offline runner.
struct CExecutionResult {
    let output: String
    let warnings: [String]
    let duration: TimeInterval
}

/// Domain errors that can be raised when compiling/executing code.
enum CCompilerError: LocalizedError {
    case syntax(message: String)
    case runtime(message: String)
    case unsupported(message: String)
    case internalError(message: String)

    var errorDescription: String? {
        switch self {
        case .syntax(let message):
            return "Syntax error: \(message)"
        case .runtime(let message):
            return "Runtime error: \(message)"
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
        do {
            let sanitized = preprocess(source: source)
            var lexer = CLexer(source: sanitized)
            let tokens = try lexer.tokenize()
            var parser = CParser(tokens: tokens)
            let statements = try parser.parseProgram()
            var interpreter = CInterpreter()
            let stdout = try interpreter.execute(statements: statements)
            let warnings = parser.warnings + interpreter.warnings
            let duration = Date().timeIntervalSince(startedAt)
            return .success(CExecutionResult(output: stdout, warnings: warnings, duration: duration))
        } catch let error as CCompilerError {
            return .failure(error)
        } catch {
            return .failure(.internalError(message: error.localizedDescription))
        }
    }

    private func preprocess(source: String) -> String {
        source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
            .joined(separator: "\n")
    }
}

// MARK: - Lexer

private enum Token: Equatable {
    case keyword(String)
    case identifier(String)
    case number(Int)
    case stringLiteral(String)
    case symbol(String)
}

private struct CLexer {
    private let characters: [Character]
    private var index: Int = 0

    private static let keywords: Set<String> = [
        "int", "return", "if", "else", "while", "for", "break", "continue"
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

            if let symbol = readSymbol() {
                tokens.append(.symbol(symbol))
                continue
            }

            throw CCompilerError.syntax(message: "Unexpected character '\(current)'")
        }

        return tokens
    }

    private mutating func readNumber() -> Token {
        var value = ""
        while let current = peek(), current.isNumber {
            value.append(current)
            _ = advance()
        }
        return .number(Int(value) ?? 0)
    }

    private mutating func readIdentifier() -> Token {
        var value = ""
        while let current = peek(), current.isLetter || current.isNumber || current == "_" {
            value.append(current)
            _ = advance()
        }
        if CLexer.keywords.contains(value) {
            return .keyword(value)
        } else {
            return .identifier(value)
        }
    }

    private mutating func readStringLiteral() throws -> Token {
        _ = advance() // Opening quote
        var buffer = ""
        while let current = peek() {
            if current == "\"" {
                _ = advance()
                return .stringLiteral(buffer)
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
        throw CCompilerError.syntax(message: "Unterminated string literal")
    }

    private mutating func readSymbol() -> String? {
        if let compound = CLexer.compoundSymbols.first(where: matches(symbol:)) {
            index += compound.count
            return compound
        }

        guard let char = advance() else { return nil }
        return String(char)
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
        throw CCompilerError.syntax(message: "Unterminated block comment")
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
        guard match(keyword: "int") else {
            throw CCompilerError.syntax(message: "Entry point must start with 'int main()'")
        }
        guard case .identifier("main")? = advance() else {
            throw CCompilerError.syntax(message: "Expected 'main' function")
        }
        try consumeParameterList()
        return try parseBlock()
    }

    private mutating func consumeParameterList() throws {
        guard match(symbol: "(") else {
            throw CCompilerError.syntax(message: "Expected '(' after main")
        }
        var depth = 1
        while depth > 0 {
            guard let token = advance() else {
                throw CCompilerError.syntax(message: "Unterminated parameter list")
            }
            if case .symbol("(") = token {
                depth += 1
            } else if case .symbol(")") = token {
                depth -= 1
            }
        }
    }

    private mutating func parseBlock() throws -> [Statement] {
        guard match(symbol: "{") else {
            throw CCompilerError.syntax(message: "Expected '{' to start block")
        }
        var statements: [Statement] = []
        while !check(symbol: "}") {
            if isAtEnd {
                throw CCompilerError.syntax(message: "Unterminated block")
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

        if match(keyword: "int") {
            return try parseDeclaration()
        }

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

        if case .identifier("printf")? = peek() {
            _ = advance()
            return try parsePrintfCall()
        }

        if match(symbol: ";") {
            return .empty
        }

        return try parseAssignmentLikeStatement()
    }

    private mutating func parseDeclaration(expectTerminator: Bool = true) throws -> Statement {
        guard case .identifier(let name)? = advance() else {
            throw CCompilerError.syntax(message: "Expected identifier after 'int'")
        }
        var initialValue: Expression?
        if match(symbol: "=") {
            initialValue = try parseExpression()
        }
        if expectTerminator {
            try consume(symbol: ";")
        }
        return .declaration(name: name, value: initialValue)
    }

    private mutating func parseAssignmentLikeStatement(expectTerminator: Bool = true) throws -> Statement {
        guard case .identifier(let name)? = advance() else {
            throw CCompilerError.syntax(message: "Expected identifier")
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

        guard case .symbol(let symbol)? = advance() else {
            throw CCompilerError.syntax(message: "Expected assignment operator after identifier '\(name)'")
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
        guard case .stringLiteral(let format)? = advance() else {
            throw CCompilerError.syntax(message: "printf expects a string literal as the first argument")
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
        if match(keyword: "int") {
            return try parseDeclaration(expectTerminator: false)
        }
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
            throw CCompilerError.syntax(message: "Unexpected end of expression")
        }
        switch token {
        case .number(let value):
            return .number(value)
        case .identifier(let name):
            return .identifier(name)
        default:
            throw CCompilerError.syntax(message: "Unexpected token in expression")
        }
    }

    private func currentBinaryOperator() -> BinaryOperator? {
        guard case .symbol(let symbol)? = peek() else { return nil }
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
        guard match(symbol: symbol) else {
            throw CCompilerError.syntax(message: "Expected '\(symbol)'")
        }
    }

    private mutating func match(symbol: String) -> Bool {
        guard case .symbol(let value)? = peek(), value == symbol else { return false }
        _ = advance()
        return true
    }

    private mutating func match(keyword: String) -> Bool {
        guard case .keyword(let value)? = peek(), value == keyword else { return false }
        _ = advance()
        return true
    }

    private func check(symbol: String) -> Bool {
        guard case .symbol(let value)? = peek() else { return false }
        return value == symbol
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
        throw CCompilerError.runtime(message: "Variable '\(name)' used before declaration")
    }

    func value(of name: String) throws -> Int {
        for scope in scopes.reversed() {
            if let value = scope[name] {
                return value
            }
        }
        throw CCompilerError.runtime(message: "Variable '\(name)' used before declaration")
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
                guard rhs != 0 else { throw CCompilerError.runtime(message: "Division by zero") }
                newValue = try context.value(of: name) / rhs
            case .mod:
                guard rhs != 0 else { throw CCompilerError.runtime(message: "Modulo by zero") }
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
                guard right != 0 else { throw CCompilerError.runtime(message: "Division by zero") }
                return left / right
            case .mod:
                guard right != 0 else { throw CCompilerError.runtime(message: "Modulo by zero") }
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
