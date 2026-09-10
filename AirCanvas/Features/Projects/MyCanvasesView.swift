import SwiftUI
import UniformTypeIdentifiers

struct MyCanvasesView: View {
    @State private var viewModel: MyCanvasesViewModel
    @State private var projectToRename: CanvasProjectSummary?
    @State private var projectToDelete: CanvasProjectSummary?
    @State private var renameDraft = ""
    @State private var isImporting = false

    init(repository: any CanvasProjectRepository) {
        _viewModel = State(initialValue: MyCanvasesViewModel(repository: repository))
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView("Loading Canvases")
            case .loaded(let projects) where projects.isEmpty:
                ContentUnavailableView {
                    Label("No Canvases Yet", systemImage: "square.stack.3d.up")
                } description: {
                    Text("Create a spatial canvas to begin drawing.")
                } actions: {
                    NavigationLink(value: AppRoute.canvas(.new)) {
                        Label("Create a New Canvas", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .loaded(let projects):
                List(projects) { project in
                    NavigationLink(value: AppRoute.canvas(.existing(project.id))) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(project.name)
                                .font(.headline)
                                .lineLimit(2)
                            Text("Updated \(project.modifiedAt.formatted(date: .abbreviated, time: .shortened)) • \(project.strokeCount) \(project.strokeCount == 1 ? "stroke" : "strokes")")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel(project.name)
                    .accessibilityValue("Updated \(project.modifiedAt.formatted(date: .abbreviated, time: .shortened)), \(project.strokeCount) \(project.strokeCount == 1 ? "stroke" : "strokes")")
                    .accessibilityHint("Opens this canvas")
                    .accessibilityIdentifier("canvasCard.open")
                    .contextMenu {
                        Button("Rename", systemImage: "pencil") {
                            projectToRename = project
                            renameDraft = project.name
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            projectToDelete = project
                        }
                        Button("Duplicate", systemImage: "plus.square.on.square") {
                            Task { await viewModel.duplicate(project) }
                        }
                    }
                }
                .listStyle(.plain)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn’t Load Canvases", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") {
                        Task { await viewModel.refresh() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("My Canvases")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    isImporting = true
                } label: {
                    Label("Import Canvas", systemImage: "square.and.arrow.down")
                }
                .accessibilityLabel("Import AirCanvas document")
                .accessibilityIdentifier("myCanvases.import")
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: AppRoute.canvas(.new)) {
                    Label("New Canvas", systemImage: "plus")
                }
                .accessibilityLabel("Create new canvas")
                .accessibilityIdentifier("myCanvases.create")
            }
        }
        .task {
            await viewModel.refresh()
        }
        .onAppear {
            Task { await viewModel.refresh() }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.airCanvasDocument],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    viewModel.recordImportError(AirCanvasDocumentError.invalidDocument)
                    return
                }
                Task { await viewModel.importDocument(at: url) }
            case .failure(let error):
                viewModel.recordImportError(error)
            }
        }
        .alert("Couldn’t Import Canvas", isPresented: importErrorPresentationBinding) {
            Button("OK", role: .cancel) {
                viewModel.dismissImportError()
            }
        } message: {
            Text(viewModel.importErrorMessage ?? "The selected AirCanvas document could not be read.")
        }
        .alert("Rename Canvas", isPresented: renamePresentationBinding) {
            TextField("Canvas name", text: $renameDraft)
            Button("Cancel", role: .cancel) {
                projectToRename = nil
            }
            Button("Save") {
                guard let project = projectToRename else {
                    return
                }
                projectToRename = nil
                Task { await viewModel.rename(project, to: renameDraft) }
            }
        }
        .confirmationDialog(
            "Delete \(projectToDelete?.name ?? "Canvas")?",
            isPresented: deletePresentationBinding,
            titleVisibility: .visible
        ) {
            Button("Delete Canvas", role: .destructive) {
                guard let project = projectToDelete else {
                    return
                }
                projectToDelete = nil
                Task { await viewModel.delete(project) }
            }
        } message: {
            Text("This will remove this canvas and its saved spatial content.")
        }
    }

    private var renamePresentationBinding: Binding<Bool> {
        Binding(
            get: { projectToRename != nil },
            set: { if !$0 { projectToRename = nil } }
        )
    }

    private var deletePresentationBinding: Binding<Bool> {
        Binding(
            get: { projectToDelete != nil },
            set: { if !$0 { projectToDelete = nil } }
        )
    }

    private var importErrorPresentationBinding: Binding<Bool> {
        Binding(
            get: { viewModel.importErrorMessage != nil },
            set: { if !$0 { viewModel.dismissImportError() } }
        )
    }
}

#Preview {
    NavigationStack {
        MyCanvasesView(repository: FileCanvasProjectRepository())
    }
}
