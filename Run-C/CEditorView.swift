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

// MARK: - Code Editor View (UIViewRepresentable)

struct CodeEditorView: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.isScrollEnabled = true
        textView.backgroundColor = .white // White background for code editor
        textView.layer.cornerRadius = 8
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        textView.attributedText = CSyntaxHighlighter.highlight(text: text)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        guard uiView.text != text else { return }
        let selectedRange = uiView.selectedTextRange
        uiView.attributedText = CSyntaxHighlighter.highlight(text: text)
        uiView.selectedTextRange = selectedRange
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
            textView.attributedText = CSyntaxHighlighter.highlight(text: textView.text)
            textView.selectedTextRange = selectedRange
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

    @State private var code: String = CEditorView.template
    @State private var consoleOutput: String = "Tap Run to execute your program offline."
    @State private var warnings: [String] = []
    @State private var errorMessage: String?
    @State private var duration: TimeInterval?
    @State private var lastRunDate: Date?
    @State private var isRunning = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            CodeEditorView(text: $code)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal)
                .padding(.top, 12)
            Divider()
            consoleView
        }
        .navigationTitle("C Sandbox")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button("Reset") {
                    code = CEditorView.template
                }
                .disabled(isRunning)

                Button(action: runCode) {
                    if isRunning {
                        ProgressView()
                    } else {
                        Label("Run", systemImage: "play.fill")
                    }
                }
                .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRunning)
                .accessibilityLabel("Run C code")
            }
        }
        .tint(.blue) // Set accent color for buttons
        .onAppear {
            // Customize navigation bar appearance for this view
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor.systemBlue // Blue background
            appearance.titleTextAttributes = [.foregroundColor: UIColor.white] // White title
            appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white] // White large title
            
            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
            UINavigationBar.appearance().compactAppearance = appearance
        }
        .animation(.default, value: warnings)
        .animation(.default, value: errorMessage)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Offline C Compiler")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Code never leaves the device. Supports basic control flow, math and printf.")
                .font(.footnote)
                .foregroundColor(.secondary)
            if let duration, let lastRunDate {
                Text(String(format: "Last run %@ · %.2f ms",
                            lastRunDate.formatted(date: .omitted, time: .standard),
                            duration * 1000))
                .font(.footnote)
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white) // White background for header
    }

    private var consoleView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Console", systemImage: "terminal.fill")
                    .font(.headline)
                Spacer()
                if isRunning {
                    Text("Running…")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            ScrollView {
                Text(outputText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.white) // White background for console output
                    .cornerRadius(8)
            }

            if !warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Warnings", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                    ForEach(warnings, id: \.self) { warning in
                        Text("• \(warning)")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color.white) // White background for console view
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
        warnings.removeAll()
        duration = nil
        consoleOutput = ""

        Task.detached(priority: .userInitiated) {
            let runner = OfflineCCompiler()
            let result = runner.run(source: source)
            await MainActor.run {
                isRunning = false
                lastRunDate = Date()
                switch result {
                case .success(let execution):
                    consoleOutput = execution.output
                    warnings = execution.warnings
                    duration = execution.duration
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        CEditorView()
    }
}
