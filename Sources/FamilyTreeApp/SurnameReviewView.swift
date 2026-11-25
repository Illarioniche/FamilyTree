import SwiftUI
import FamilyTreeCore

struct SurnameReviewView: View {
    @ObservedObject var store: FamilyStore
    @Environment(\.dismiss) private var dismiss
    private let suggestions: [SurnameRepairSuggestion]
    @State private var selected: Set<UUID>

    init(store: FamilyStore) {
        self.store = store
        let proposals = store.surnameRepairSuggestions
        suggestions = proposals
        _selected = State(initialValue: Set(proposals.map(\.personID)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Основная и девичья фамилии")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                Text("Проверьте фамилии из старого импорта. Выберите людей, для которых сохранённую дополнительную фамилию нужно сделать основной, а прежнюю — девичьей.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    Button("Выбрать все") { selected = Set(suggestions.map(\.personID)) }
                    Button("Снять выбор") { selected.removeAll() }
                    Spacer()
                    Text("Выбрано: \(selected.count) из \(suggestions.count)").monospacedDigit()
                }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Palette.accent)
            }.padding(24)
            Divider()
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(suggestions) { suggestion in
                        HStack(alignment: .top, spacing: 12) {
                            Toggle("Изменить фамилии: \(suggestion.personName)", isOn: Binding(
                                get: { selected.contains(suggestion.personID) },
                                set: { if $0 { selected.insert(suggestion.personID) } else { selected.remove(suggestion.personID) } }
                            )).toggleStyle(.checkbox).labelsHidden().padding(.top, 2)
                            VStack(alignment: .leading, spacing: 9) {
                                Text(suggestion.personName).font(.system(size: 13, weight: .medium))
                                    .fixedSize(horizontal: false, vertical: true)
                                HStack(alignment: .top, spacing: 16) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Сейчас").font(.system(size: 10)).foregroundStyle(.secondary)
                                        Text(suggestion.previousFamilyName).font(.system(size: 12))
                                    }.frame(width: 150, alignment: .leading)
                                    Image(systemName: "arrow.right").font(.system(size: 11))
                                        .foregroundStyle(Palette.accent).padding(.top, 17)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Основная: \(suggestion.proposedFamilyName)")
                                        Text("Девичья: \(suggestion.proposedMaidenName)").foregroundStyle(.secondary)
                                    }.font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                    if suggestions.isEmpty {
                        Text("Фамилии для разделения не найдены.")
                            .font(.system(size: 13)).foregroundStyle(.secondary).padding(30)
                    }
                }.padding(20)
            }
            Divider()
            HStack(spacing: 14) {
                Text("Изменение можно отменить через ⌘Z.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Применить (\(selected.count))") {
                    store.applySurnameRepairs(suggestions.filter { selected.contains($0.personID) })
                    dismiss()
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(selected.isEmpty)
            }.padding(20)
        }.frame(width: 680, height: 600).background(Palette.canvas).tint(Palette.accent)
    }
}
