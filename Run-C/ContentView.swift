import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            CEditorView()
                .navigationTitle("Run-C")
        }
    }
}

#Preview {
    NavigationStack {
        CEditorView()
    }
}
