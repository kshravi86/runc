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
                            .foregroundColor(.primary) // Ensure primary text is visible
                        
                        Text(note.content ?? "")
                            .font(.body)
                            .foregroundColor(.secondary) // Secondary text
                            .lineLimit(2)
                        
                        Text(note.modifiedDate ?? Date(), style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary) // Secondary text
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
        .tint(.blue) // Set accent color for navigation links and buttons
        .onAppear {
            // Customize navigation bar appearance
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor.systemBlue // Blue background
            appearance.titleTextAttributes = [.foregroundColor: UIColor.white] // White title
            appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white] // White large title
            
            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
            UINavigationBar.appearance().compactAppearance = appearance
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