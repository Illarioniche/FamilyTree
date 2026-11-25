import SwiftUI
import FamilyTreeCore

struct TreeLibraryView: View {
    @ObservedObject var store: FamilyStore

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
                                TreeLibraryCard(entry: entry, isCurrent: isCurrent(entry)) {
                                    store.openLibraryTree(entry)
                                }
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

private struct TreeLibraryCard: View {
    let entry: TreeLibraryEntry
    let isCurrent: Bool
    let open: () -> Void

    var body: some View {
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
