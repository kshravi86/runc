import SwiftUI
import CoreData

struct NoteDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String
    @State private var content: String
    
    let note: Note?
    
    init(note: Note?) {
        self.note = note
        _title = State(initialValue: note?.title ?? "")
        _content = State(initialValue: note?.content ?? "")
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                TextField("Title", text: $title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding()
                    .background(Color(.systemGray6))
                
                TextEditor(text: $content)
                    .padding()
                    .background(Color(.systemBackground))
            }
            .navigationTitle(note == nil ? "New Note" : "Edit Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveNote()
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func saveNote() {
        withAnimation {
            let noteToSave: Note
            
            if let existingNote = note {
                noteToSave = existingNote
            } else {
                noteToSave = Note(context: viewContext)
                noteToSave.createdDate = Date()
            }
            
            noteToSave.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            noteToSave.content = content
            noteToSave.modifiedDate = Date()
            
            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
}

#Preview {
    NoteDetailView(note: nil)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}