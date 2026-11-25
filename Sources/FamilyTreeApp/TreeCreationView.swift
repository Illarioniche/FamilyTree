import SwiftUI
import FamilyTreeCore

struct TreeCreationView: View {
    @ObservedObject var store: FamilyStore
    let request: TreeCreationRequest
    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFocused: Bool
    @State private var title: String
    @State private var showingWarnings = false

    init(store: FamilyStore, request: TreeCreationRequest) {
        self.store = store
        self.request = request
        _title = State(initialValue: TreeLibrary.displayTitle(request.project.title))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 13) {
                    Image(systemName: request.isImport ? "square.and.arrow.down" : "leaf.fill")
                        .font(.system(size: 23, weight: .light)).foregroundStyle(Palette.accent)
                        .frame(width: 50, height: 50)
                        .background(Palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 15))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(request.isImport ? "Импортировать дерево" : "Новое дерево")
                            .font(.system(size: 23, weight: .semibold, design: .rounded))
                        Text(request.isImport ? "История семьи готова к переносу" : "Начните историю вашей семьи")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Название дерева").font(.system(size: 12, weight: .medium))
                    TextField("Например, Семья Волковых", text: $title)
                        .textFieldStyle(.roundedBorder).controlSize(.large)
                        .focused($titleFocused).onSubmit(create)
                        .accessibilityLabel("Название дерева")
                    Text("Это название будет отображаться в «Моих деревьях». Его можно изменить позже.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if request.isImport {
                    Label("Людей в дереве: \(request.project.people.count)", systemImage: "person.2")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                if !request.warnings.isEmpty {
                    DisclosureGroup("Замечания к импорту (\(request.warnings.count))", isExpanded: $showingWarnings) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(request.warnings.enumerated()), id: \.offset) { _, warning in
                                    Text(warning).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }.padding(.top, 8)
                        }.frame(maxHeight: 130)
                    }.font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if let error = store.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.system(size: 11)).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.padding(28)
            Divider()
            HStack(spacing: 12) {
                Label("Сохранится на этом Mac", systemImage: "internaldrive")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button("Отмена") {
                    store.treeCreation = nil
                    dismiss()
                }.keyboardShortcut(.cancelAction)
                Button(request.isImport ? "Импортировать" : "Создать дерево", action: create)
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(22)
        }
        .frame(width: 540).background(Palette.canvas).tint(Palette.accent)
        .onAppear { titleFocused = true }
    }

    private func create() {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        store.completeTreeCreation(title: name)
    }
}
