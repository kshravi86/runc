import SwiftUI
import UIKit

// MARK: - Syntax Highlighting Logic

struct CSyntaxHighlighter {
    private static let keywords = [
        "auto", "break", "case", "char", "const", "continue", "default", "do", "double",
        "else", "enum", "extern", "float", "for", "goto", "if", "int", "long", "register",
        "return", "short", "signed", "sizeof", "static", "struct", "switch", "typedef",
        "union", "unsigned", "void", "volatile", "while", "printf"
    ]

    // (helper functions removed; they belong to CEditorView)

    private static let keywordPattern = "\\b(" + keywords.joined(separator: "|") + ")\\b"
    private static let commentPattern = "//.*|/\\*.*?\\*/"
    private static let stringPattern = "\"(\\\\.|[^\"])*\""

    private static let keywordColor = UIColor.systemBlue.withAlphaComponent(0.8)
    private static let commentColor = UIColor.systemGreen.withAlphaComponent(0.7)
    private static let stringColor = UIColor.systemOrange.withAlphaComponent(0.8)
    private static let defaultColor = UIColor.label
    private static let errorColor = UIColor.systemRed.withAlphaComponent(0.2)

    static func highlight(text: String) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: attributedString.length)

        attributedString.addAttribute(.foregroundColor, value: defaultColor, range: fullRange)
        attributedString.addAttribute(
            .font,
            value: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            range: fullRange
        )

        applyHighlighting(
            to: attributedString,
            pattern: keywordPattern,
            color: keywordColor
        )
        applyHighlighting(
            to: attributedString,
            pattern: commentPattern,
            color: commentColor,
            options: [.dotMatchesLineSeparators]
        )
        applyHighlighting(
            to: attributedString,
            pattern: stringPattern,
            color: stringColor
        )

        // Naive semicolon heuristic to help newcomers catch missing terminators.
        markSuspiciousLines(in: attributedString, text: text)
        return attributedString
    }

    static func highlight(text: String, errorLine: Int?) -> NSAttributedString {
        let attributed = NSMutableAttributedString(attributedString: highlight(text: text))
        if let errorLine, errorLine > 0 {
            let nsText = attributed.string as NSString
            var currentLine = 1
            var location = 0
            let length = nsText.length
            while currentLine < errorLine && location < length {
                let range = nsText.range(of: "\n", options: [], range: NSRange(location: location, length: length - location))
                if range.location == NSNotFound { break }
                location = range.location + 1
                currentLine += 1
            }
            if currentLine == errorLine {
                let lineEndRange = nsText.range(of: "\n", options: [], range: NSRange(location: location, length: max(0, length - location)))
                let lineLen = lineEndRange.location == NSNotFound ? (length - location) : (lineEndRange.location - location)
                let lineRange = NSRange(location: location, length: max(0, lineLen))
                attributed.addAttribute(.backgroundColor, value: UIColor.systemRed.withAlphaComponent(0.25), range: lineRange)
            }
        }
        return attributed
    }

    private static func applyHighlighting(
        to attributedString: NSMutableAttributedString,
        pattern: String,
        color: UIColor,
        options: NSRegularExpression.Options = []
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return
        }

        let matches = regex.matches(
            in: attributedString.string,
            options: [],
            range: NSRange(location: 0, length: attributedString.length)
        )

        for match in matches {
            attributedString.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }

    private static func markSuspiciousLines(
        in attributedString: NSMutableAttributedString,
        text: String
    ) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var offset = 0

        for line in lines {
            let content = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty &&
                !content.hasPrefix("#") &&
                !content.hasPrefix("//") &&
                !content.hasPrefix("/*") &&
                !content.hasSuffix(";") &&
                !content.hasSuffix("{") &&
                !content.hasSuffix("}") {
                let range = NSRange(location: offset, length: line.count)
                attributedString.addAttribute(.backgroundColor, value: errorColor, range: range)
            }
            offset += line.count + 1
        }
    }
}

/// A custom input accessory view for the keyboard, providing quick access to common C symbols.
private class SymbolInputAccessoryView: UIView {
    weak var targetTextView: UITextView?

    init(target: UITextView) {
        self.targetTextView = target
        super.init(frame: .zero)
        self.autoresizingMask = .flexibleHeight
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: 44)
    }

    private func setupView() {
        let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 0, height: 44))
        toolbar.autoresizingMask = .flexibleWidth
        
        let symbols = [
            "{", "}", ";", "(", ")", "[", "]", "=", "+", "-", "*", "/", "%", "<", ">", "&", "|"
        ]
        
        var items: [UIBarButtonItem] = []
        
        for symbol in symbols {
            let button = UIBarButtonItem(title: symbol, style: .plain, target: self, action: #selector(symbolTapped(_:)))
            items.append(button)
            items.append(UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil))
        }
        
        // Add a flexible space to push the last item to the right (optional, but good practice)
        items.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))
        
        // Add a "Done" button to dismiss the keyboard
        let doneButton = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(doneTapped))
        items.append(doneButton)
        
        toolbar.items = items
        addSubview(toolbar)
        
        // Constraints for the toolbar
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: topAnchor),
            toolbar.bottomAnchor.constraint(equalTo: bottomAnchor),
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    @objc private func symbolTapped(_ sender: UIBarButtonItem) {
        guard let textView = targetTextView, let symbol = sender.title else { return }
        
        // Insert the symbol at the current cursor position
        textView.insertText(symbol)
        
        // Simple auto-closing logic for brackets/parentheses
        if symbol == "{" {
            textView.insertText("}")
            // Move cursor back one position
            if let newPosition = textView.selectedTextRange?.start {
                let offset = textView.offset(from: textView.beginningOfDocument, to: newPosition)
                let newCursorPosition = textView.position(from: textView.beginningOfDocument, offset: offset - 1)
                textView.selectedTextRange = textView.textRange(from: newCursorPosition!, to: newCursorPosition!)
            }
        } else if symbol == "(" {
            textView.insertText(")")
            if let newPosition = textView.selectedTextRange?.start {
                let offset = textView.offset(from: textView.beginningOfDocument, to: newPosition)
                let newCursorPosition = textView.position(from: textView.beginningOfDocument, offset: offset - 1)
                textView.selectedTextRange = textView.textRange(from: newCursorPosition!, to: newCursorPosition!)
            }
        } else if symbol == "[" {
            textView.insertText("]")
            if let newPosition = textView.selectedTextRange?.start {
                let offset = textView.offset(from: textView.beginningOfDocument, to: newPosition)
                let newCursorPosition = textView.position(from: textView.beginningOfDocument, offset: offset - 1)
                textView.selectedTextRange = textView.textRange(from: newCursorPosition!, to: newCursorPosition!)
            }
        }
    }

    @objc private func doneTapped() {
        targetTextView?.resignFirstResponder()
    }
}

// MARK: - Code Editor View (UIViewRepresentable)

/// A custom UIView that hosts the UITextView and a line number gutter.
final class CodeEditorHostView: UIView {
    let textView: UITextView
    let lineNumberGutter: LineNumberGutterView
    var errorLine: Int?

    init(text: Binding<String>, coordinator: CodeEditorView.Coordinator, errorLine: Int?) {
        self.textView = UITextView()
        self.lineNumberGutter = LineNumberGutterView(textView: textView)
        self.errorLine = errorLine
        super.init(frame: .zero)

        // Configure TextView
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.isScrollEnabled = true
        textView.backgroundColor = .systemBackground
        textView.layer.cornerRadius = 8
        textView.translatesAutoresizingMaskIntoConstraints = false
        
        // Add subviews
        addSubview(lineNumberGutter)
        addSubview(textView)

        // Constraints
        NSLayoutConstraint.activate([
            // Gutter constraints
            lineNumberGutter.topAnchor.constraint(equalTo: topAnchor),
            lineNumberGutter.bottomAnchor.constraint(equalTo: bottomAnchor),
            lineNumberGutter.leadingAnchor.constraint(equalTo: leadingAnchor),
            lineNumberGutter.widthAnchor.constraint(equalToConstant: 40),

            // TextView constraints
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.leadingAnchor.constraint(equalTo: lineNumberGutter.trailingAnchor, constant: -8) // Overlap for seamless look
        ])
        
        // Adjust text container inset to make space for the gutter
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        
        // Set initial text and highlight
        textView.attributedText = CSyntaxHighlighter.highlight(text: text.wrappedValue, errorLine: errorLine)
        
        // Set up scroll synchronization
        textView.delegate = coordinator
        
        // Set up input accessory view
        textView.inputAccessoryView = SymbolInputAccessoryView(target: textView)
        
        // Initial update of line numbers
        lineNumberGutter.updateLineNumbers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// A simple view to draw line numbers.
final class LineNumberGutterView: UIView {
    weak var textView: UITextView?
    
    init(textView: UITextView) {
        self.textView = textView
        super.init(frame: .zero)
        self.backgroundColor = .secondarySystemBackground
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updateLineNumbers() {
        guard let textView = textView else { return }
        
        // Clear existing labels
        subviews.forEach { $0.removeFromSuperview() }
        
        let text = textView.text ?? ""
        let lines = text.components(separatedBy: .newlines)
        let font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let lineHeight = font.lineHeight
        
        // Calculate the starting Y offset based on the text view's content inset and scroll offset
        var yOffset: CGFloat = textView.textContainerInset.top - textView.contentOffset.y
        
        for (index, _) in lines.enumerated() {
            let lineNumber = index + 1
            let label = UILabel()
            label.text = "\(lineNumber)"
            label.font = font
            label.textColor = .tertiaryLabel
            label.textAlignment = .right
            
            let labelHeight = lineHeight
            let labelY = yOffset + (lineHeight - labelHeight) / 2
            label.frame = CGRect(x: 0, y: labelY, width: bounds.width - 8, height: labelHeight)
            
            // Only add labels that are visible or near visible
            if labelY + labelHeight > 0 && labelY < bounds.height {
                addSubview(label)
            }
            
            yOffset += lineHeight
        }
    }
}

struct CodeEditorView: UIViewRepresentable {
    @Binding var text: String
    var errorLine: Int?

    func makeUIView(context: Context) -> CodeEditorHostView {
        let hostView = CodeEditorHostView(text: $text, coordinator: context.coordinator, errorLine: errorLine)
        return hostView
    }

    func updateUIView(_ uiView: CodeEditorHostView, context: Context) {
        uiView.errorLine = errorLine
        if uiView.textView.text != text || errorLine != nil {
            let selectedRange = uiView.textView.selectedTextRange
            uiView.textView.attributedText = CSyntaxHighlighter.highlight(text: text, errorLine: errorLine)
            uiView.textView.selectedTextRange = selectedRange
        }
        uiView.lineNumberGutter.updateLineNumbers()
        if let errorLine {
            scroll(textView: uiView.textView, toLine: errorLine)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        let parent: CodeEditorView

        init(_ parent: CodeEditorView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            let selectedRange = textView.selectedTextRange
            textView.attributedText = CSyntaxHighlighter.highlight(text: textView.text, errorLine: parent.errorLine)
            textView.selectedTextRange = selectedRange
            
            // Force update line numbers on text change
            if let hostView = textView.superview as? CodeEditorHostView {
                hostView.lineNumberGutter.updateLineNumbers()
            }
        }
        
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            // Synchronize the gutter's scroll position
            if let hostView = scrollView.superview as? CodeEditorHostView {
                hostView.lineNumberGutter.updateLineNumbers()
            }
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // Auto-indent on newline
            if text == "\n" {
                let ns = textView.text as NSString? ?? "" as NSString
                let beforeRange = NSRange(location: 0, length: range.location)
                let beforeText = ns.substring(with: beforeRange)
                if let lastNewline = beforeText.lastIndex(of: "\n") {
                    let lineStart = beforeText.index(after: lastNewline)
                    let currentLine = String(beforeText[lineStart..<beforeText.endIndex])
                    let indentPrefix = currentLine.prefix { $0 == "\t" || $0 == " " }
                    var extraIndent = ""
                    if currentLine.trimmingCharacters(in: .whitespaces).hasSuffix("{") {
                        extraIndent = "    "
                    }
                    let insertion = "\n" + String(indentPrefix) + extraIndent
                    let maxLen = (textView.attributedText?.length ?? ns.length)
                    if range.location <= maxLen && range.location + range.length <= maxLen {
                        let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
                        mutable.replaceCharacters(in: range, with: insertion)
                        textView.attributedText = mutable
                        let pos = range.location + (insertion as NSString).length
                        if let start = textView.position(from: textView.beginningOfDocument, offset: pos) {
                            textView.selectedTextRange = textView.textRange(from: start, to: start)
                        }
                        self.textViewDidChange(textView)
                        return false
                    }
                }
            }
            // Auto-pair common characters
            let pairs: [String: String] = ["(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'"]
            if let closing = pairs[text], let selectedRange = textView.selectedTextRange, selectedRange.isEmpty {
                let insertion = text + closing
                let caretAdvance = (text as NSString).length
                let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
                mutable.replaceCharacters(in: range, with: insertion)
                textView.attributedText = mutable
                let newOffset = range.location + caretAdvance
                if let start = textView.position(from: textView.beginningOfDocument, offset: newOffset) {
                    textView.selectedTextRange = textView.textRange(from: start, to: start)
                }
                self.textViewDidChange(textView)
                return false
            }
            return true
        }
    }

    private func scroll(textView: UITextView, toLine line: Int) {
        let text = textView.text as NSString? ?? "" as NSString
        var currentLine = 1
        var location = 0
        let length = text.length
        while currentLine < line && location < length {
            let r = text.range(of: "\n", options: [], range: NSRange(location: location, length: length - location))
            if r.location == NSNotFound { break }
            location = r.location + 1
            currentLine += 1
        }
        if currentLine == line {
            let range = NSRange(location: location, length: 0)
            textView.scrollRangeToVisible(range)
        }
    }
}

// MARK: - Host View

struct CEditorView: View {
    private static let template = """
    #include <stdio.h>

    int main(void) {
        int sum = 0;
        for (int i = 0; i < 5; i += 1) {
            sum += i;
        }
        printf("Sum is %d\\n", sum);
        return 0;
    }
    """

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme

    @State private var code: String = CEditorView.template
    @State private var consoleOutput: String = "Tap Run to execute your program offline."
    @State private var warnings: [String] = []
    @State private var errorMessage: String?
    @State private var errorLine: Int?
    @State private var duration: TimeInterval?
    @State private var lastRunDate: Date?
    @State private var isRunning = false
    @State private var lastLoadedCode: String = CEditorView.template
    @State private var pendingSample: SampleProgram?
    @State private var showReplaceConfirm = false
    @State private var selectedConsoleTab: ConsoleTab = .output
    @State private var didAutoRun = false
    @State private var selectedSample: SampleProgram?

    struct SampleProgram: Identifiable, Hashable {
        let id = UUID()
        let title: String
        let code: String
        let description: String = ""
        let order: Int? = nil
    }

    private let samples: [SampleProgram] = [
        SampleProgram(
            title: "Hello World",
            code: """
            #include <stdio.h>

            int main(void) {
                printf("Hello, world!\\n");
                return 0;
            }
            """
        ),
        SampleProgram(
            title: "For Loop Sum",
            code: """
            #include <stdio.h>

            int main(void) {
                int sum = 0;
                for (int i = 1; i <= 10; i += 1) {
                    sum += i;
                }
                printf("Sum 1..10 = %d\\n", sum);
                return 0;
            }
            """
        ),
        SampleProgram(
            title: "If/Else",
            code: """
            #include <stdio.h>

            int main(void) {
                int x = 7;
                if (x % 2 == 0) {
                    printf("%d is even\\n", x);
                } else {
                    printf("%d is odd\\n", x);
                }
                return 0;
            }
            """
        ),
        SampleProgram(
            title: "Fibonacci",
            code: """
            #include <stdio.h>

            int main(void) {
                int n = 10;
                int a = 0, b = 1;
                printf("Fibonacci: ");
                for (int i = 0; i < n; i += 1) {
                    printf("%d ", a);
                    int next = a + b;
                    a = b;
                    b = next;
                }
                printf("\\n");
                return 0;
            }
            """
        ),
        SampleProgram(
            title: "Average 1..5",
            code: """
            #include <stdio.h>

            int main(void) {
                int sum = 0;
                for (int i = 1; i <= 5; i += 1) {
                    sum += i;
                }
                int avg = sum / 5; // integer division
                printf("Average = %d\\n", avg);
                return 0;
            }
            """
        )
        ,
        SampleProgram(
            title: "FizzBuzz 1..20",
            code: """
            #include <stdio.h>

            int main(void) {
                for (int i = 1; i <= 20; i += 1) {
                    if (i % 15 == 0) {
                        printf("FizzBuzz\\n");
                    } else if (i % 3 == 0) {
                        printf("Fizz\\n");
                    } else if (i % 5 == 0) {
                        printf("Buzz\\n");
                    } else {
                        printf("%d\\n", i);
                    }
                }
                return 0;
            }
            """
        ),
        SampleProgram(
            title: "Factorial (iterative)",
            code: """
            #include <stdio.h>

            int main(void) {
                int n = 6;
                int fact = 1;
                for (int i = 2; i <= n; i += 1) {
                    fact = fact * i;
                }
                printf("%d! = %d\\n", n, fact);
                return 0;
            }
            """
        ),
        SampleProgram(
            title: "GCD (Euclid)",
            code: """
            #include <stdio.h>

            int main(void) {
                int a = 84;
                int b = 60;
                while (b != 0) {
                    int t = a % b;
                    a = b;
                    b = t;
                }
                printf("GCD = %d\\n", a);
                return 0;
            }
            """
        ),
        SampleProgram(
            title: "Prime Check",
            code: """
            #include <stdio.h>

            int main(void) {
                int n = 29;
                int isPrime = 1;
                if (n < 2) { isPrime = 0; }
                for (int i = 2; i * i <= n; i += 1) {
                    if (n % i == 0) { isPrime = 0; }
                }
                if (isPrime) {
                    printf("%d is prime\\n", n);
                } else {
                    printf("%d is not prime\\n", n);
                }
                return 0;
            }
            """
        ),
        SampleProgram(
            title: "Multiplication Table (7)",
            code: """
            #include <stdio.h>

            int main(void) {
                int n = 7;
                for (int i = 1; i <= 10; i += 1) {
                    int p = n * i;
                    printf("%d x %d = %d\\n", n, i, p);
                }
                return 0;
            }
            """
        ),
        SampleProgram(
            title: "Countdown (while)",
            code: """
            #include <stdio.h>

            int main(void) {
                int i = 5;
                while (i >= 0) {
                    printf("%d\\n", i);
                    i = i - 1;
                }
                printf("Blast off!\\n");
                return 0;
            }
            """
        ),
        SampleProgram(
            title: "Power (loop)",
            code: """
            #include <stdio.h>

            int main(void) {
                int base = 3;
                int exp = 5;
                int result = 1;
                for (int i = 0; i < exp; i += 1) {
                    result = result * base;
                }
                printf("%d^%d = %d\\n", base, exp, result);
                return 0;
            }
            """
        ),
        SampleProgram(
            title: "Max of Three",
            code: """
            #include <stdio.h>

            int main(void) {
                int a = 10, b = 25, c = 17;
                int max = a;
                if (b > max) { max = b; }
                if (c > max) { max = c; }
                printf("max = %d\\n", max);
                return 0;
            }
            """
        ),
        SampleProgram(
            title: "Hex and Char",
            code: """
            #include <stdio.h>

            int main(void) {
                int x = 255;
                printf("dec=%d hex=%X char=%c\\n", x, x, 65);
                return 0;
            }
            """
        ),
        SampleProgram(
            title: "Collatz Steps",
            code: """
            #include <stdio.h>

            int main(void) {
                int n = 27;
                int steps = 0;
                while (n != 1) {
                    if (n % 2 == 0) {
                        n = n / 2;
                    } else {
                        n = 3 * n + 1;
                    }
                    steps = steps + 1;
                }
                printf("steps = %d\\n", steps);
                return 0;
            }
            """
        )
    ]

    // Beginner path and descriptions for sidebar
    private var beginnerSamples: [SampleProgram] {
        samples.filter { beginnerOrder($0) != nil }
            .sorted { (beginnerOrder($0) ?? Int.max) < (beginnerOrder($1) ?? Int.max) }
    }

    private var otherSamples: [SampleProgram] {
        let beginnerSet = Set(beginnerSamples.map { $0.id })
        return samples.filter { !beginnerSet.contains($0.id) }
    }

    private func sampleDescription(_ sample: SampleProgram) -> String {
        switch sample.title {
        case "Hello World": return "Your first program and printf"
        case "For Loop Sum": return "Use a for loop and integer math"
        case "If/Else": return "Branch using conditions"
        case "Countdown (while)": return "Use a while loop and decrement"
        case "Multiplication Table (7)": return "Nested printf inside a for loop"
        case "Average 1..5": return "Compute an average with a loop"
        case "FizzBuzz 1..20": return "Practice modulo and branching"
        case "Max of Three": return "Track a running maximum"
        case "Factorial (iterative)": return "Multiply in a loop"
        case "Power (loop)": return "Repeated multiplication builds powers"
        case "Prime Check": return "Detect primes efficiently (i*i <= n)"
        case "GCD (Euclid)": return "Greatest common divisor via modulo"
        case "Fibonacci": return "Sequence with temporary variables"
        case "Hex and Char": return "Format integers as hex and chars"
        case "Collatz Steps": return "While loop practice with odd/even"
        default: return ""
        }
    }

    private func beginnerOrder(_ sample: SampleProgram) -> Int? {
        switch sample.title {
        case "Hello World": return 1
        case "For Loop Sum": return 2
        case "If/Else": return 3
        case "Countdown (while)": return 4
        case "Multiplication Table (7)": return 5
        case "Average 1..5": return 6
        case "FizzBuzz 1..20": return 7
        case "Max of Three": return 8
        case "Factorial (iterative)": return 9
        case "Power (loop)": return 10
        case "Prime Check": return 11
        case "GCD (Euclid)": return 12
        case "Fibonacci": return 13
        case "Hex and Char": return 14
        case "Collatz Steps": return 15
        default: return nil
        }
    }

    private enum ConsoleTab: String, Identifiable {
        case output = "Output"
        case warnings = "Warnings"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .output:
                return "terminal.fill"
            case .warnings:
                return "exclamationmark.triangle.fill"
            }
        }
    }

    private var isWideLayout: Bool {
        horizontalSizeClass == .regular
    }

    private var cardShadow: Color {
        Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            HStack(alignment: .top, spacing: isWideLayout ? 20 : 12) {
                sidebar

                VStack(spacing: isWideLayout ? 20 : 16) {
                    header
                    if isWideLayout {
                        HStack(alignment: .top, spacing: 20) {
                            editorSection
                            consoleSection
                        }
                    } else {
                        editorSection
                        consoleSection
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .padding(.top, isWideLayout ? 24 : 12)
            .padding(.horizontal, isWideLayout ? 24 : 12)
            .padding(.bottom, 16)
        }
        // Navigation title is provided by parent (ContentView),
        // avoid duplicate/overlapping titles.
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button("Reset") {
                    code = CEditorView.template
                    lastLoadedCode = CEditorView.template
                    selectedConsoleTab = .output
                }
                .disabled(isRunning)

                Button(action: runCode) {
                    HStack(spacing: 6) {
                        if isRunning {
                            ProgressView()
                        } else {
                            Image(systemName: "play.fill")
                        }
                        Text(isRunning ? "Running" : "Run")
                            .fontWeight(.semibold)
                    }
                }
                .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRunning)
                .accessibilityLabel("Run C code")
            }
        }
        .tint(.blue) // Set accent color for buttons
        .background(Color(.systemGroupedBackground)) // Use system-adaptive background for a sleek look
        .animation(.default, value: warnings)
        .animation(.default, value: errorMessage)
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if !didAutoRun && args.contains("--auto-run") {
                if let first = samples.first {
                    apply(first)
                }
                didAutoRun = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    runCode()
                }
            }
        }
    }

    private var sidebar: some View {
        let sideWidth: CGFloat = isWideLayout ? 220 : 160
        return VStack(alignment: .leading, spacing: 12) {
            Label("Programs", systemImage: "list.bullet")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Beginner Path")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.top, 4)

                    ForEach(beginnerSamples) { sample in
                        let isSelected = selectedSample?.id == sample.id
                        Button {
                            selectedSample = sample
                            select(sample)
                        } label: {
                            HStack {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(isSelected ? .accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sample.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    if !sampleDescription(sample).isEmpty {
                                        Text(sampleDescription(sample))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Divider().padding(.vertical, 6)
                    Text("More Programs")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)

                    ForEach(otherSamples) { sample in
                        let isSelected = selectedSample?.id == sample.id
                        Button {
                            selectedSample = sample
                            select(sample)
                        } label: {
                            HStack {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(isSelected ? .accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sample.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    if !sampleDescription(sample).isEmpty {
                                        Text(sampleDescription(sample))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }

            Spacer(minLength: 0)
        }
        .frame(width: sideWidth, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.05 : 0.2))
        )
        .shadow(color: cardShadow.opacity(0.6), radius: 14, y: 8)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Offline C Compiler")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Code never leaves the device. Supports basic control flow, math and printf.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let lastRunDate {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("Last run")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(lastRunDate.formatted(date: .numeric, time: .shortened))
                            .font(.subheadline.weight(.semibold))
                        if let duration {
                            Text(String(format: "%.2f ms", duration * 1000))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            statusBadges
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.05 : 0.25))
        )
        .shadow(color: cardShadow, radius: 22, y: 12)
    }

    private var editorSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Source", systemImage: "chevron.left.slash.chevron.right")
                    .font(.headline)
                Spacer()
            }

            editorMetrics

            CodeEditorView(text: $code, errorLine: errorLine)
                .frame(height: isWideLayout ? 420 : 320)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(.separator).opacity(0.2))
                )
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .shadow(color: cardShadow, radius: 24, y: 14)
    }

    private var consoleSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(selectedConsoleTab.rawValue, systemImage: selectedConsoleTab.icon)
                    .font(.headline.weight(.semibold))
                Spacer()
                if isRunning {
                    Text("Running…")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else if let errorMessage, !errorMessage.isEmpty {
                    Text("Build failed")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.red)
                } else {
                    Text(lastRunDate == nil ? "Idle" : "Ready")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            if availableConsoleTabs.count > 1 {
                Picker("Console section", selection: $selectedConsoleTab) {
                    ForEach(availableConsoleTabs) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
            }

            Group {
                switch selectedConsoleTab {
                case .output:
                    ScrollView {
                        Text(outputText)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .textSelection(.enabled)
                    }
                case .warnings:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(warnings, id: \.self) { warning in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                        .font(.headline)
                                    Text(warning)
                                        .font(.footnote.monospaced())
                                        .foregroundColor(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(14)
                                .background(Color.orange.opacity(colorScheme == .dark ? 0.2 : 0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: isWideLayout ? 280 : 240, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(.separator).opacity(0.12))
        )
        .shadow(color: cardShadow, radius: 24, y: 14)
        .onChange(of: warnings) { newValue in
            if newValue.isEmpty {
                selectedConsoleTab = .output
            }
        }
    }

    private var statusBadges: some View {
        HStack(spacing: 10) {
            if isRunning {
                statusBadge(text: "Running", systemImage: "bolt.fill", foreground: .blue)
            } else if errorMessage != nil {
                statusBadge(text: "Build failed", systemImage: "xmark.octagon.fill", foreground: .red)
            } else if lastRunDate == nil {
                statusBadge(
                    text: "Ready",
                    systemImage: "sparkles",
                    foreground: .secondary,
                    background: Color(.tertiarySystemGroupedBackground)
                )
            } else {
                statusBadge(text: "Last run OK", systemImage: "checkmark.circle.fill", foreground: .green)
            }
        }
    }

    private var editorMetrics: some View {
        HStack(spacing: 10) {
            statusBadge(
                text: "\(codeLineCount) lines",
                systemImage: "number",
                foreground: Color.primary.opacity(0.8),
                background: Color(.tertiarySystemGroupedBackground)
            )
            statusBadge(
                text: "\(codeCharacterCount) chars",
                systemImage: "textformat",
                foreground: Color.primary.opacity(0.8),
                background: Color(.tertiarySystemGroupedBackground)
            )
        }
    }

    private func statusBadge(
        text: String,
        systemImage: String,
        foreground: Color,
        background: Color? = nil
    ) -> some View {
        let fill = background ?? foreground.opacity(colorScheme == .dark ? 0.3 : 0.15)
        return Label {
            Text(text)
                .font(.footnote.weight(.semibold))
        } icon: {
            Image(systemName: systemImage)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(fill)
        )
        .foregroundColor(foreground)
    }

    private var outputText: String {
        if let errorMessage {
            return errorMessage
        }
        return consoleOutput.isEmpty ? "(Program finished without output)" : consoleOutput
    }

    private func runCode() {
        let source = code
        isRunning = true
        errorMessage = nil
        errorLine = nil
        warnings.removeAll()
        duration = nil
        selectedConsoleTab = .output
        consoleOutput = ""
        Log.info("Run button tapped (lines=\(codeLineCount), chars=\(codeCharacterCount))", category: .ui)

        Task.detached(priority: .userInitiated) {
            let runner = OfflineCCompiler()
            let result = runner.run(source: source)
            await MainActor.run {
                isRunning = false
                lastRunDate = Date()
                switch result {
                case .success(let execution):
                    Log.info("Execution success: duration=\(String(format: "%.3f", execution.duration))s, warnings=\(execution.warnings.count), outputLen=\(execution.output.count)", category: .ui)
                    consoleOutput = execution.output
                    warnings = execution.warnings
                    duration = execution.duration
                    lastLoadedCode = source
                    if execution.warnings.isEmpty {
                        selectedConsoleTab = .output
                    }
                case .failure(let error):
                    Log.warn("Execution failure shown to user: \(error.localizedDescription)", category: .ui)
                    errorMessage = error.localizedDescription
                    // Extract line number when available
                    switch error {
                    case .syntax(_, let line), .runtime(_, let line):
                        errorLine = line
                    default:
                        break
                    }
                    selectedConsoleTab = .output
                }
            }
        }
    }

    private func select(_ sample: SampleProgram) {
        // Ask before replacing if there are unsaved edits
        if code != lastLoadedCode && !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pendingSample = sample
            showReplaceConfirm = true
        } else {
            apply(sample)
        }
    }

    private func apply(_ sample: SampleProgram) {
        Log.info("Applying sample: \(sample.title) (chars=\(sample.code.count))", category: .editor)
        code = sample.code
        lastLoadedCode = sample.code
        errorMessage = nil
        errorLine = nil
        warnings.removeAll()
        selectedConsoleTab = .output
    }

    private var availableConsoleTabs: [ConsoleTab] {
        warnings.isEmpty ? [.output] : [.output, .warnings]
    }

    private var codeLineCount: Int {
        max(1, code.split(separator: "\n", omittingEmptySubsequences: false).count)
    }

    private var codeCharacterCount: Int {
        code.count
    }
}

extension CEditorView {
    @ViewBuilder
    var replaceConfirmation: some View {
        EmptyView()
            .confirmationDialog(
                "Replace current code with sample?",
                isPresented: $showReplaceConfirm,
                titleVisibility: .visible
            ) {
                Button("Replace", role: .destructive) {
                    if let s = pendingSample { apply(s) }
                    pendingSample = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingSample = nil
                }
            }
    }
}

#Preview {
    NavigationStack {
        CEditorView()
    }
}
