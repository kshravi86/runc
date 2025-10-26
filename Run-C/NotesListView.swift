import SwiftUI
import CoreData

struct NotesListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Note.modifiedDate, ascending: false)],
        animation: .default)
    private var notes: FetchedResults<Note>
    
    @State private var showingAddNote = false

    var body: some View {
        List {
            ForEach(notes) { note in
                NavigationLink(destination: NoteDetailView(note: note)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.title ?? "Untitled")
                            .font(.headline)
                            .lineLimit(1)
                        
                        Text(note.content ?? "")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                        
                        Text(note.modifiedDate ?? Date(), style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .onDelete(perform: deleteNotes)
        }
        .navigationTitle("Notes")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: addNote) {
                    Label("Add Note", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                NavigationLink {
                    CEditorView()
                } label: {
                    Label("C Editor", systemImage: "c.circle")
                }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                EditButton()
            }
        }
        .sheet(isPresented: $showingAddNote) {
            NoteDetailView(note: nil)
        }
    }

    private func addNote() {
        showingAddNote = true
    }

    private func deleteNotes(offsets: IndexSet) {
        withAnimation {
            offsets.map { notes[$0] }.forEach(viewContext.delete)

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
    NotesListView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}