import SwiftUI
import AppKit
import FamilyTreeCore

struct TreeLibraryView: View {
    @ObservedObject var store: FamilyStore
    @State private var pendingRemoval: TreeRemovalRequest?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 23, weight: .medium)).foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Palette.accent.gradient, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 3) {
                    Text("FamilyTree").font(.system(size: 21, weight: .semibold, design: .rounded))
                    Text("Всё начинается с семьи").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if store.fileURL != nil || store.hasUnsavedChanges {
                    Button { store.showingTreeLibrary = false } label: {
                        Label("Вернуться к дереву", systemImage: "arrow.right")
                    }.buttonStyle(.bordered)
                } else {
                    Button("Посмотреть пример", action: store.showExample)
                        .buttonStyle(.plain).foregroundStyle(Palette.accent)
                }
            }
            .padding(.horizontal, 48).padding(.top, 34).padding(.bottom, 36)

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(alignment: .bottom, spacing: 20) {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionCaption(title: "Ваша семейная история")
                            Text("Мои деревья")
                                .font(.system(size: 32, weight: .semibold, design: .rounded))
                            Text("Каждой семье — своя история.")
                                .font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        if !store.savedTrees.isEmpty { libraryActions }
                    }

                    if store.savedTrees.isEmpty {
                        emptyLibrary
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 18)], spacing: 18) {
                            ForEach(store.savedTrees) { entry in
                                TreeLibraryCard(
                                    entry: entry, isCurrent: isCurrent(entry),
                                    canTrash: store.canTrashTree(entry), canForget: store.canForgetTree(entry),
                                    open: { store.openLibraryTree(entry) },
                                    delete: { pendingRemoval = TreeRemovalRequest(entry: entry, forgetOnly: false) },
                                    forget: { pendingRemoval = TreeRemovalRequest(entry: entry, forgetOnly: true) }
                                )
                            }
                        }
                    }
                }
                .frame(maxWidth: 1120, alignment: .leading)
                .padding(.horizontal, 48).padding(.bottom, 36)
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 8) {
                Image(systemName: "internaldrive").foregroundStyle(Palette.accent)
                Text("Деревья сохраняются на этом Mac. Аккаунт и интернет не нужны.")
                    .foregroundStyle(.secondary)
                Spacer()
            }.font(.system(size: 11))
                .padding(.horizontal, 48).padding(.vertical, 22)
                .overlay(alignment: .top) { Rectangle().fill(Palette.divider).frame(height: 1) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.canvas).tint(Palette.accent)
        .alert(pendingRemoval?.title ?? "Удалить дерево?", isPresented: Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } }
        ), presenting: pendingRemoval) { request in
            Button(request.forgetOnly ? "Убрать из списка" : "Переместить в Корзину", role: .destructive) {
                if request.forgetOnly { _ = store.forgetUnavailableTree(request.entry) }
                else { _ = store.deleteTree(request.entry) }
            }
            Button("Отмена", role: .cancel) { }
        } message: { request in
            Text(request.message)
        }
    }

    private var libraryActions: some View {
        VStack(alignment: .trailing, spacing: 9) {
            HStack(spacing: 10) {
                Button(action: store.importTree) {
                    Label("Импортировать из файла", systemImage: "square.and.arrow.down")
                }.buttonStyle(.bordered)
                Button(action: store.newProject) {
                    Label("Создать дерево", systemImage: "plus")
                }.buttonStyle(.borderedProminent)
            }.controlSize(.large)
            Text("FamilyTree или GEDCOM")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private var emptyLibrary: some View {
        VStack(spacing: 16) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 46, weight: .ultraLight)).foregroundStyle(Palette.accent)
                .frame(width: 108, height: 108)
                .background(Palette.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 30))
            Text("Здесь начинается история вашей семьи")
                .font(.system(size: 23, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
            Text("Создайте первое дерево или перенесите уже собранную историю из другого приложения.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 420)
            HStack(spacing: 12) {
                Button(action: store.newProject) {
                    Label("Создать дерево", systemImage: "plus")
                }.buttonStyle(.borderedProminent)
                Button(action: store.importTree) {
                    Label("Импортировать из файла", systemImage: "square.and.arrow.down")
                }.buttonStyle(.bordered)
            }.controlSize(.large).padding(.top, 8)
            Text("Поддерживаются деревья FamilyTree и GEDCOM")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24).padding(.vertical, 44)
        .frame(maxWidth: .infinity)
        .background(Palette.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Palette.divider, lineWidth: 1))
    }

    private func isCurrent(_ entry: TreeLibraryEntry) -> Bool {
        guard !store.isExample, let current = store.fileURL else { return false }
        return current.standardizedFileURL.resolvingSymlinksInPath()
            == entry.url.standardizedFileURL.resolvingSymlinksInPath()
    }
}

private struct TreeRemovalRequest {
    let entry: TreeLibraryEntry
    let forgetOnly: Bool

    var title: String {
        forgetOnly ? "Убрать дерево из списка?" : "Удалить дерево «\(entry.title)»?"
    }

    var message: String {
        let explanation = forgetOnly
            ? "Запись исчезнет из библиотеки. Сам файл останется без изменений. Его можно будет открыть снова, когда он станет доступен."
            : "Дерево со всеми людьми, фотографиями и документами, а также его резервная копия (если есть) будут перемещены в Корзину. Оттуда их можно восстановить."
        return explanation + "\n\nФайл: " + entry.url.path
    }
}

private struct TreeLibraryCard: View {
    let entry: TreeLibraryEntry
    let isCurrent: Bool
    let canTrash: Bool
    let canForget: Bool
    let open: () -> Void
    let delete: () -> Void
    let forget: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            openButton
            Menu { cardActions } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Palette.accent.opacity(0.06), in: Circle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .padding(.top, 29).padding(.trailing, 22)
            .help("Действия с деревом")
            .accessibilityLabel("Действия с деревом «\(entry.title)»")
        }
        .contextMenu { cardActions }
    }

    @ViewBuilder private var cardActions: some View {
        if entry.issue == nil {
            Button("Открыть дерево", systemImage: "arrow.up.right", action: open)
        }
        if entry.url.isFileURL {
            Button("Показать в Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([entry.url])
            }
        }
        if canTrash || canForget { Divider() }
        if canTrash {
            Button("Удалить дерево…", systemImage: "trash", role: .destructive, action: delete)
        }
        if canForget {
            Button("Убрать из списка…", systemImage: "minus.circle", action: forget)
        }
    }

    private var openButton: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 8) {
                    Image(systemName: entry.issue == nil ? "leaf.fill" : "exclamationmark.triangle")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(entry.issue == nil ? Palette.accent : .secondary)
                        .frame(width: 44, height: 44)
                        .background(Palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
                    Spacer(minLength: 4)
                    if isCurrent {
                        Text("ОТКРЫТО")
                            .font(.system(size: 8, weight: .semibold)).tracking(0.8)
                            .foregroundStyle(Palette.accent)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Palette.accent.opacity(0.08), in: Capsule())
                    }
                    Color.clear.frame(width: 30, height: 30)
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text(entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Семейное дерево" : entry.title)
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .lineLimit(2).frame(height: 44, alignment: .topLeading)
                    if let issue = entry.issue {
                        Text(issue).font(.system(size: 11)).foregroundStyle(.secondary)
                            .lineLimit(3).frame(minHeight: 31, alignment: .topLeading)
                    } else {
                        Label(peopleCount, systemImage: "person.2")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Text("Изменено \(entry.modifiedAt.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "ru_RU"))))")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Text(entry.issue == nil ? "Открыть дерево" : "Дерево недоступно")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Image(systemName: entry.issue == nil ? "arrow.up.right" : "exclamationmark.circle")
                        .font(.system(size: 11))
                }.foregroundStyle(entry.issue == nil ? Palette.accent : .secondary)
            }
            .padding(22)
            .frame(maxWidth: .infinity, minHeight: 225, alignment: .topLeading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(isCurrent ? Palette.accent.opacity(0.45) : Palette.divider, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 17))
        }.buttonStyle(.plain).disabled(entry.issue != nil)
            .accessibilityLabel(entry.title)
            .accessibilityHint(entry.issue ?? "Открыть семейное дерево")
    }

    private var peopleCount: String {
        let count = entry.peopleCount
        let tens = count % 100
        let suffix = (11...14).contains(tens) ? "человек"
            : count % 10 == 1 ? "человек" : (2...4).contains(count % 10) ? "человека" : "человек"
        return "\(count) \(suffix)"
    }
}
