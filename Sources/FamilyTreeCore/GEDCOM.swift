import Foundation

public struct GEDCOMImportResult: Sendable {
    public var project: FamilyProject
    public var warnings: [String]
    public init(project: FamilyProject, warnings: [String]) {
        self.project = project; self.warnings = warnings
    }
}

public enum GEDCOMError: LocalizedError {
    case invalidEncoding, malformedLine(Int), missingHeader, noPeople, duplicateReference(String), invalidReference(String)
    public var errorDescription: String? {
        switch self {
        case .invalidEncoding: return "Не удалось прочитать кодировку GEDCOM. Экспортируйте файл в UTF-8 или UTF-16 с BOM."
        case .malformedLine(let line): return "Некорректная структура GEDCOM в строке \(line)."
        case .missingHeader: return "Это не файл GEDCOM: отсутствует заголовок HEAD."
        case .noPeople: return "В файле GEDCOM нет записей о людях."
        case .duplicateReference(let ref): return "В GEDCOM повторяется идентификатор \(ref)."
        case .invalidReference(let ref): return "В GEDCOM отсутствует человек или семья, на которых ссылается запись \(ref)."
        }
    }
}

/// A deliberately bounded exchange layer, not a lossless replacement for .familytree.
/// Imports the common genealogy subset of GEDCOM 5.5.1 and 7; never reads linked files or URLs.
/// Export uses GEDCOM 5.5.1 UTF-8. Attachments, favorite flags and source citations are omitted.
/// _FT_* extensions preserve patronymics, maiden names, exact date text and event kinds
/// when the file is reopened by this application; other programs may ignore these extensions.
public enum GEDCOM {
    public static func importData(_ data: Data, title: String = "Импортированное дерево") throws -> GEDCOMImportResult {
        let source: String
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            guard let decoded = String(data: data, encoding: .utf16) else { throw GEDCOMError.invalidEncoding }
            source = decoded
        } else {
            guard let decoded = String(data: data, encoding: .utf8) else { throw GEDCOMError.invalidEncoding }
            source = decoded
        }
        let records = try parse(source)
        guard let head = records.first, head.tag == "HEAD" else { throw GEDCOMError.missingHeader }
        let isFamytale = head.child("SOUR")?.value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "FAMYTALE"
        var warnings: [String] = []
        func warn(_ value: String) { if !warnings.contains(value) { warnings.append(value) } }
        if records.last?.tag != "TRLR" { warn("В файле нет завершающей записи TRLR; прочитанные записи импортированы.") }
        let version = head.child("GEDC")?.child("VERS")?.value ?? ""
        if !version.hasPrefix("5.5") && !version.hasPrefix("7.") {
            warn("Версия GEDCOM \(version.isEmpty ? "не указана" : version). Импортирована поддерживаемая часть данных.")
        }
        let charset = head.child("CHAR")?.value.uppercased() ?? "UTF-8"
        if !["UTF-8", "UTF8", "UNICODE", "ASCII"].contains(charset) { throw GEDCOMError.invalidEncoding }
        var recordsByRef: [String: Node] = [:]
        for record in records {
            if let ref = record.reference {
                guard recordsByRef[ref] == nil else { throw GEDCOMError.duplicateReference(ref) }
                recordsByRef[ref] = record
            }
        }
        func noteText(_ node: Node, visited: Set<String> = []) -> String {
            if isPointer(node.value) {
                guard !visited.contains(node.value), let linked = recordsByRef[node.value], ["NOTE", "SNOTE"].contains(linked.tag) else {
                    warn("Одна или несколько ссылок на заметки не удалось прочитать.")
                    return ""
                }
                return noteText(linked, visited: visited.union([node.value]))
            }
            return node.text
        }
        func notes(_ node: Node) -> String {
            node.children.filter { ["NOTE", "SNOTE"].contains($0.tag) }.map { noteText($0) }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        }
        func dateText(_ node: Node?) -> String {
            guard let node else { return "" }
            if let original = node.child("_FT_DATE") { return original.text }
            if let phrase = node.child("PHRASE"), node.value.isEmpty { return phrase.text }
            let value = node.value
            if value.hasPrefix("("), value.hasSuffix(")") { return String(value.dropFirst().dropLast()) }
            return value
        }
        let individualRecords = records.filter { $0.tag == "INDI" }
        guard !individualRecords.isEmpty else { throw GEDCOMError.noPeople }
        var project = FamilyProject(title: head.child("_FT_TITLE")?.text ?? title)
        var personIDs: [String: UUID] = [:]
        var usedIDs = Set<UUID>()
        for record in individualRecords {
            guard let ref = record.reference else { throw GEDCOMError.invalidReference("INDI без идентификатора") }
            var id = UUID(uuidString: record.child("_UID")?.value ?? record.child("UID")?.value ?? "") ?? UUID()
            if usedIDs.contains(id) { id = UUID(); warn("Повторяющийся UUID человека заменён новым идентификатором.") }
            usedIDs.insert(id); personIDs[ref] = id
            let names = record.children.filter { $0.tag == "NAME" }
            let name = names.first
            let pieces = (name?.text ?? "").components(separatedBy: "/")
            let firstPart = pieces.first?.trimmingCharacters(in: .whitespaces) ?? ""
            let surname = pieces.count > 1 ? pieces[1].trimmingCharacters(in: .whitespaces) : ""
            let given = name?.child("GIVN")?.text ?? firstPart
            let primarySurname = name?.child("SURN")?.text ?? surname
            var person = Person(id: id,
                                givenName: name?.child("_FT_GIVEN")?.text ?? given,
                                patronymic: name?.child("_FT_PATRONYMIC")?.text ?? "",
                                familyName: primarySurname,
                                maidenName: record.child("_FT_MAIDEN")?.text ?? "")
            switch record.child("SEX")?.value.uppercased() {
            case "M": person.gender = .male
            case "F": person.gender = .female
            default: person.gender = .unspecified
            }
            if let birth = record.child("BIRT") {
                person.birthDate = dateText(birth.child("DATE")); person.birthPlace = birth.child("PLAC")?.text ?? ""
                if !notes(birth).isEmpty { project.events.append(FamilyEvent(personID: id, kind: .birth, title: "Рождение", date: person.birthDate, place: person.birthPlace, notes: notes(birth))) }
            }
            if let death = record.child("DEAT"), death.value.uppercased() != "N" {
                person.isDeceased = true; person.deathDate = dateText(death.child("DATE"))
                let place = death.child("PLAC")?.text ?? ""
                if !place.isEmpty || !notes(death).isEmpty { project.events.append(FamilyEvent(personID: id, kind: .death, title: "Уход из жизни", date: person.deathDate, place: place, notes: notes(death))) }
            }
            person.occupation = record.child("OCCU")?.text ?? ""
            person.biography = notes(record)
            func preserveName(_ value: String, fromGEDCOM: Bool = false) {
                guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                person.biography += (person.biography.isEmpty ? "" : "\n\n")
                    + (fromGEDCOM ? "Другое имя из GEDCOM: " : "Другое имя: ") + value
            }
            // NAME order expresses preference. Typed alternatives supply a maiden
            // surname, but never replace the preferred (first) main name.
            for (index, alternate) in names.enumerated() {
                let type = alternate.child("TYPE")?.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
                var represented = false
                var conflict = false
                if ["maiden", "birth"].contains(type), let alternateSurname = surnameFromName(alternate) {
                    if person.maidenName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        person.maidenName = alternateSurname
                    }
                    represented = sameName(person.maidenName, alternateSurname)
                    conflict = !represented
                    if conflict {
                        warn("Разные девичьи фамилии в _FT_MAIDEN и NAME TYPE birth/maiden сохранены без замены выбранной фамилии; альтернативы добавлены в биографии.")
                    }
                    let parts = alternate.text.components(separatedBy: "/")
                    // GIVN keeps the original spelling; NAME replaces literal
                    // slashes with spaces. Decode escapes and CONC before checking
                    // either form, while retaining real differences in patronymics.
                    if let structuredGiven = alternate.child("GIVN")?.text,
                       !structuredGiven.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       !sameName(structuredGiven, given) { represented = false }
                    if let displayedGiven = parts.first,
                       !displayedGiven.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       !sameName(displayedGiven, given.replacingOccurrences(of: "/", with: " ")) { represented = false }
                    if parts.count > 1, !sameName(parts[1], alternateSurname.replacingOccurrences(of: "/", with: " ")) { represented = false }
                    if parts.dropFirst(2).contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { represented = false }
                }
                if (index > 0 && !represented) || conflict {
                    let text = alternate.text
                    let structuredDisplay = [alternate.child("GIVN")?.text, surnameFromName(alternate)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
                    preserveName(text.isEmpty ? structuredDisplay : text.replacingOccurrences(of: "/", with: ""))
                    // Conflicting structured GIVN is also evidence; the raw NAME
                    // alone cannot preserve it when the two forms disagree.
                    if !text.isEmpty, let structuredGiven = alternate.child("GIVN")?.text,
                       !structuredGiven.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       !sameName(structuredGiven, given),
                       !sameName(structuredGiven.replacingOccurrences(of: "/", with: " "), text.components(separatedBy: "/").first ?? "") {
                        preserveName(structuredDisplay)
                    }
                }
            }
            // FamyTale's one-name dialect stores the birth surname in SURN and
            // the married surname in _MARNM. Restrict this interpretation to its
            // explicit source ID and a single unambiguous surname. Other dialects,
            // multiple names and full-name payloads remain available as notes.
            var seenOtherNames = Set<String>()
            let otherNames = names.flatMap { $0.children.filter { $0.tag == "_MARNM" }.map(\.text) }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && seenOtherNames.insert($0.lowercased()).inserted }
            let primaryType = name?.child("TYPE")?.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            var mappedMarriedName = false
            if isFamytale, names.count == 1, otherNames.count == 1,
               let marriedSurname = otherNames.first, isSimpleSurname(marriedSurname),
               !primarySurname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               ["", "birth", "maiden"].contains(primaryType),
               sameName(marriedSurname, primarySurname) || person.maidenName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sameName(person.maidenName, primarySurname) {
                if !sameName(marriedSurname, primarySurname) {
                    person.familyName = marriedSurname
                    if person.maidenName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { person.maidenName = primarySurname }
                }
                mappedMarriedName = true
            }
            if !mappedMarriedName {
                for otherName in otherNames {
                    preserveName(otherName, fromGEDCOM: true)
                    warn("Дополнительные имена и фамилии из _MARNM сохранены в биографиях. Основное имя и девичья фамилия не изменены автоматически.")
                }
            }
            for component in ["NPFX", "NSFX", "NICK", "SPFX"] {
                if let extra = name?.child(component), !extra.text.isEmpty {
                    person.biography += (person.biography.isEmpty ? "" : "\n\n") + "\(component): \(extra.text)"
                    warn("Приставки, суффиксы и прозвища из NAME сохранены в биографии.")
                }
            }
            if person.givenName.isEmpty && person.familyName.isEmpty { person.givenName = "Без имени" }
            for event in record.children where ["RESI", "EDUC", "GRAD", "EVEN", "EMIG", "IMMI", "BURI", "CREM", "BAPM", "CHR", "RETI", "CENS", "NATU", "ADOP", "MARR", "OCCU"].contains(event.tag) {
                if event.tag == "OCCU" && event.child("DATE") == nil && event.child("PLAC") == nil && notes(event).isEmpty { continue }
                let kind = event.child("_FT_KIND").flatMap { EventKind(rawValue: $0.value) } ?? kindForTag(event.tag)
                let eventTitle = event.child("TYPE")?.text ?? (event.tag == "EVEN" && !event.value.isEmpty && event.value != "Y" ? event.text : titleForTag(event.tag))
                project.events.append(FamilyEvent(personID: id, kind: kind, title: eventTitle, date: dateText(event.child("DATE")), place: event.child("PLAC")?.text ?? "", notes: notes(event)))
            }
            project.people.append(person)
        }
        func individualID(_ reference: String) throws -> UUID {
            guard let id = personIDs[reference] else { throw GEDCOMError.invalidReference(reference) }
            return id
        }
        var relationKeys = Set<String>()
        func appendRelation(_ from: UUID, _ to: UUID, _ kind: RelationshipKind) throws {
            guard from != to else { throw GEDCOMError.invalidReference("связь человека с самим собой") }
            let ids = kind == .partner ? [from.uuidString, to.uuidString].sorted() : [from.uuidString, to.uuidString]
            let key = kind.rawValue + ids.joined(separator: "|")
            if relationKeys.insert(key).inserted { project.relationships.append(Relationship(fromID: from, toID: to, kind: kind)) }
        }
        let families = records.filter { $0.tag == "FAM" }
        let familyRefs = Set(families.compactMap(\.reference))
        for individual in individualRecords {
            for link in individual.children where ["FAMC", "FAMS"].contains(link.tag) {
                guard familyRefs.contains(link.value) else { throw GEDCOMError.invalidReference(link.value) }
            }
        }
        for family in families {
            guard let familyRef = family.reference else { throw GEDCOMError.invalidReference("FAM без идентификатора") }
            var parentRefs = family.children.filter { ["HUSB", "WIFE"].contains($0.tag) }.map(\.value)
            var childRefs = family.children.filter { $0.tag == "CHIL" }.map(\.value)
            // Accept a missing reciprocal link, which occurs in several real-world exporters.
            for record in individualRecords {
                guard let ref = record.reference else { continue }
                if record.children.contains(where: { $0.tag == "FAMS" && $0.value == familyRef }), !parentRefs.contains(ref) { parentRefs.append(ref) }
                if record.children.contains(where: { $0.tag == "FAMC" && $0.value == familyRef }), !childRefs.contains(ref) { childRefs.append(ref) }
            }
            parentRefs = unique(parentRefs); childRefs = unique(childRefs)
            let parents = try parentRefs.map(individualID)
            if family.child("_FT_PARTNERS")?.value != "N", parents.count > 1 {
                for index in 1..<parents.count { try appendRelation(parents[0], parents[index], .partner) }
            }
            for childRef in childRefs {
                let childID = try individualID(childRef)
                let individual = recordsByRef[childRef]!
                let famc = individual.children.first { $0.tag == "FAMC" && $0.value == familyRef }
                let pedigree = famc?.child("PEDI")?.value.lowercased() ?? ""
                let adoption = individual.children.first { $0.tag == "ADOP" && $0.child("FAMC")?.value == familyRef }
                let role = adoption?.child("FAMC")?.child("ADOP")?.value.uppercased() ?? "BOTH"
                if !pedigree.isEmpty && !["birth", "adopted"].contains(pedigree) { warn("Родство PEDI \(pedigree) импортировано как родительская связь; уточните тип после импорта.") }
                for parentRef in parentRefs {
                    let isAdopted = pedigree == "adopted" || (adoption != nil && (role == "BOTH" || family.child(role)?.value == parentRef))
                    try appendRelation(try individualID(parentRef), childID, isAdopted ? .adoptiveParent : .parent)
                }
            }
            for event in family.children where ["MARR", "DIV", "EVEN", "ENGA", "ANUL"].contains(event.tag) {
                for id in parents {
                    project.events.append(FamilyEvent(personID: id, kind: event.tag == "MARR" ? .marriage : .other, title: event.child("TYPE")?.text ?? titleForTag(event.tag), date: dateText(event.child("DATE")), place: event.child("PLAC")?.text ?? "", notes: notes(event)))
                }
            }
        }
        project.rootPersonID = head.child("_FT_ROOT").flatMap { personIDs[$0.value] } ?? project.people.first?.id
        var unknown = Set<String>(); var omittedSources = false; var omittedMedia = false
        let known: Set<String> = ["HEAD", "TRLR", "GEDC", "VERS", "FORM", "CHAR", "LANG", "DEST", "FILE", "DATE", "TIME", "SUBM", "SUBN", "COPR", "NAME", "INDI", "FAM", "HUSB", "WIFE", "CHIL", "FAMC", "FAMS", "PEDI", "ADOP", "BIRT", "DEAT", "SEX", "GIVN", "SURN", "_MARNM", "NPFX", "NSFX", "SPFX", "NICK", "PLAC", "TYPE", "NOTE", "SNOTE", "CONT", "CONC", "RESI", "EDUC", "GRAD", "OCCU", "EVEN", "MARR", "DIV", "ENGA", "ANUL", "EMIG", "IMMI", "BURI", "CREM", "BAPM", "CHR", "RETI", "CENS", "NATU", "_UID", "UID", "_FT_GIVEN", "_FT_PATRONYMIC", "_FT_MAIDEN", "_FT_DATE", "_FT_KIND", "_FT_ROOT", "_FT_TITLE", "_FT_PARTNERS", "PHRASE"]
        func inspect(_ node: Node, inHeader: Bool) {
            if node.tag == "OBJE" { omittedMedia = true; return }
            if ["SOUR", "REPO"].contains(node.tag) && !inHeader { omittedSources = true; return }
            if !known.contains(node.tag) && !(inHeader && node.tag == "SOUR") { unknown.insert(node.tag) }
            for child in node.children { inspect(child, inHeader: inHeader || node.tag == "HEAD") }
        }
        for record in records { inspect(record, inHeader: false) }
        if omittedMedia { warn("Фотографии и документы из GEDCOM не импортированы. Внешние файлы и ссылки не открывались; добавьте вложения вручную.") }
        if omittedSources { warn("Источники и архивные ссылки SOUR/REPO пока не импортируются. Сохраните исходный GEDCOM.") }
        if !unknown.isEmpty { warn("Неподдерживаемые поля пропущены: " + unknown.sorted().joined(separator: ", ") + ". Сохраните исходный GEDCOM.") }
        try ProjectValidation.validate(project)
        return GEDCOMImportResult(project: project, warnings: warnings)
    }

    public static func export(_ project: FamilyProject) -> Data {
        var lines = ["0 HEAD", "1 SOUR FAMILYTREE", "2 NAME FamilyTree for macOS", "1 GEDC", "2 VERS 5.5.1", "2 FORM LINEAGE-LINKED", "1 CHAR UTF-8", "1 SUBM @SUB1@"]
        let personRefs = Dictionary(uniqueKeysWithValues: project.people.enumerated().map { ($0.element.id, "@I\($0.offset + 1)@") })
        func emit(_ level: Int, _ tag: String, _ value: String = "") {
            let clean = value.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            let segments = clean.components(separatedBy: "\n")
            for (index, segment) in segments.enumerated() {
                let prefix = "\(index == 0 ? level : level + 1) \(index == 0 ? tag : "CONT")"
                // 5.5.1 limits logical lines. Split at Character boundaries, never within UTF-8.
                var chunk = ""; var isFirstChunk = true
                for scalar in segment.unicodeScalars {
                    // Keep the doubled at-sign intact across CONC boundaries.
                    let unit = scalar == "@" ? "@@" : String(scalar)
                    if (chunk + unit).utf8.count > 180 {
                        lines.append((isFirstChunk ? prefix : "\(level + 1) CONC") + " " + chunk)
                        chunk = ""; isFirstChunk = false
                    }
                    chunk += unit
                }
                lines.append((isFirstChunk ? prefix : "\(level + 1) CONC") + (chunk.isEmpty ? "" : " " + chunk))
            }
        }
        func pointer(_ level: Int, _ tag: String, _ ref: String) { lines.append("\(level) \(tag) \(ref)") }
        func emitDate(_ level: Int, _ text: String) {
            guard !text.isEmpty else { return }
            emit(level, "DATE", interchangeDate(text))
            emit(level + 1, "_FT_DATE", text)
        }
        emit(1, "_FT_TITLE", project.title)
        if let id = project.rootPersonID, let ref = personRefs[id] { pointer(1, "_FT_ROOT", ref) }
        lines += ["0 @SUB1@ SUBM", "1 NAME FamilyTree user"]
        var groups: [ExportFamily] = []
        func groupIndex(_ ids: [UUID], partners: Bool, childID: UUID? = nil, adopted: Bool = false) -> Int {
            let sorted = ids.sorted { $0.uuidString < $1.uuidString }
            if let index = groups.firstIndex(where: {
                guard $0.parents == sorted else { return false }
                guard let childID, let previousKind = $0.children[childID] else { return true }
                return previousKind == adopted
            }) {
                if partners { groups[index].partners = true }
                return index
            }
            groups.append(ExportFamily(parents: sorted, partners: partners, children: [:]))
            return groups.count - 1
        }
        for relation in project.relationships where relation.kind == .partner {
            guard personRefs[relation.fromID] != nil && personRefs[relation.toID] != nil else { continue }
            _ = groupIndex([relation.fromID, relation.toID], partners: true)
        }
        for person in project.people {
            for kind in [RelationshipKind.parent, .adoptiveParent] {
                let ids = unique(project.relationships.filter { $0.toID == person.id && $0.kind == kind }.map(\.fromID)).filter { personRefs[$0] != nil }.sorted { $0.uuidString < $1.uuidString }
                var offset = 0
                while offset < ids.count {
                    let pair = Array(ids[offset..<min(offset + 2, ids.count)])
                    let index = groupIndex(pair, partners: false, childID: person.id, adopted: kind == .adoptiveParent)
                    groups[index].children[person.id] = kind == .adoptiveParent
                    offset += 2
                }
            }
        }
        for person in project.people {
            guard let ref = personRefs[person.id] else { continue }
            lines.append("0 \(ref) INDI")
            emit(1, "_UID", person.id.uuidString)
            let given = [person.givenName, person.patronymic].filter { !$0.isEmpty }.joined(separator: " ")
            emit(1, "NAME", given.replacingOccurrences(of: "/", with: " ") + " /" + person.familyName.replacingOccurrences(of: "/", with: " ") + "/")
            emit(2, "GIVN", given); emit(2, "SURN", person.familyName)
            emit(2, "_FT_GIVEN", person.givenName)
            if !person.patronymic.isEmpty { emit(2, "_FT_PATRONYMIC", person.patronymic) }
            if !person.maidenName.isEmpty {
                emit(1, "_FT_MAIDEN", person.maidenName)
                emit(1, "NAME", given.replacingOccurrences(of: "/", with: " ") + " /" + person.maidenName.replacingOccurrences(of: "/", with: " ") + "/")
                emit(2, "TYPE", "maiden")
                emit(2, "GIVN", given); emit(2, "SURN", person.maidenName)
            }
            emit(1, "SEX", person.gender == .male ? "M" : person.gender == .female ? "F" : "U")
            if !person.birthDate.isEmpty || !person.birthPlace.isEmpty {
                emit(1, "BIRT"); emitDate(2, person.birthDate)
                if !person.birthPlace.isEmpty { emit(2, "PLAC", person.birthPlace) }
            }
            if person.isDeceased { emit(1, "DEAT", "Y"); emitDate(2, person.deathDate) }
            if !person.occupation.isEmpty { emit(1, "OCCU", person.occupation) }
            if !person.biography.isEmpty { emit(1, "NOTE", person.biography) }
            for event in project.events where event.personID == person.id {
                emit(1, "EVEN"); emit(2, "TYPE", event.title.isEmpty ? event.kind.title : event.title)
                emit(2, "_FT_KIND", event.kind.rawValue); emitDate(2, event.date)
                if !event.place.isEmpty { emit(2, "PLAC", event.place) }
                if !event.notes.isEmpty { emit(2, "NOTE", event.notes) }
            }
            for (index, family) in groups.enumerated() {
                let familyRef = "@F\(index + 1)@"
                if family.parents.contains(person.id) { pointer(1, "FAMS", familyRef) }
                if let adopted = family.children[person.id] { pointer(1, "FAMC", familyRef); emit(2, "PEDI", adopted ? "adopted" : "birth") }
            }
        }
        for (index, family) in groups.enumerated() {
            lines.append("0 @F\(index + 1)@ FAM")
            emit(1, "_FT_PARTNERS", family.partners ? "Y" : "N")
            let sorted = family.parents.sorted { left, right in
                let l = project.person(left)?.gender == .male ? 0 : 1
                let r = project.person(right)?.gender == .male ? 0 : 1
                return l == r ? left.uuidString < right.uuidString : l < r
            }
            for (offset, id) in sorted.enumerated() {
                if let ref = personRefs[id] { pointer(1, offset == 0 && (sorted.count > 1 || project.person(id)?.gender != .female) ? "HUSB" : "WIFE", ref) }
            }
            for person in project.people where family.children[person.id] != nil {
                if let ref = personRefs[person.id] { pointer(1, "CHIL", ref) }
            }
        }
        lines.append("0 TRLR")
        return Data((lines.joined(separator: "\r\n") + "\r\n").utf8)
    }

    private struct ExportFamily {
        var parents: [UUID]
        var partners: Bool
        var children: [UUID: Bool]
    }
    private final class Node {
        let level: Int
        let reference: String?
        let tag: String
        let value: String
        var children: [Node] = []
        init(level: Int, reference: String?, tag: String, value: String) {
            self.level = level; self.reference = reference; self.tag = tag; self.value = value
        }
        func child(_ tag: String) -> Node? { children.first { $0.tag == tag } }
        var text: String {
            var result = value.replacingOccurrences(of: "@@", with: "@")
            for child in children {
                if child.tag == "CONT" { result += "\n" + child.text }
                if child.tag == "CONC" { result += child.text }
            }
            return result
        }
    }
    private static func parse(_ text: String) throws -> [Node] {
        let clean = text.replacingOccurrences(of: "\u{FEFF}", with: "").replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var roots: [Node] = []; var stack: [Node] = []
        for (index, raw) in clean.components(separatedBy: "\n").enumerated() {
            if raw.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let parts = raw.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count >= 2, let level = Int(parts[0]), level >= 0, level <= 99 else { throw GEDCOMError.malformedLine(index + 1) }
            var reference: String?; let tag: String; let value: String
            if isPointer(String(parts[1])) {
                reference = String(parts[1])
                guard parts.count == 3 else { throw GEDCOMError.malformedLine(index + 1) }
                let rest = parts[2].split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                guard let first = rest.first else { throw GEDCOMError.malformedLine(index + 1) }
                tag = String(first).uppercased(); value = rest.count > 1 ? String(rest[1]) : ""
            } else {
                tag = String(parts[1]).uppercased(); value = parts.count == 3 ? String(parts[2]) : ""
            }
            guard tag.range(of: #"^[A-Z_][A-Z_0-9]*$"#, options: .regularExpression) != nil else { throw GEDCOMError.malformedLine(index + 1) }
            let node = Node(level: level, reference: reference, tag: tag, value: value)
            if level == 0 { roots.append(node); stack = [node] }
            else {
                while stack.count > level { stack.removeLast() }
                guard stack.count == level, let parent = stack.last, parent.level == level - 1 else { throw GEDCOMError.malformedLine(index + 1) }
                parent.children.append(node); stack.append(node)
            }
        }
        return roots
    }
    private static func surnameFromName(_ name: Node) -> String? {
        if let surname = name.child("SURN")?.text, !surname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return surname }
        let parts = name.text.components(separatedBy: "/")
        guard parts.count > 1 else { return nil }
        let surname = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        return surname.isEmpty ? nil : surname
    }
    private static func sameName(_ first: String, _ second: String) -> Bool {
        first.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(second.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }
    private static func isSimpleSurname(_ value: String) -> Bool {
        // Space-separated compounds cannot be distinguished from full names here.
        // Preserve them in notes rather than guess or truncate.
        value.range(of: #"^\p{L}[\p{L}\p{M}]*(?:[-'’]\p{L}[\p{L}\p{M}]*)*$"#, options: .regularExpression) != nil
    }
    private static func isPointer(_ value: String) -> Bool {
        value.count > 2 && value.hasPrefix("@") && value.hasSuffix("@") && !value.dropFirst().dropLast().contains("@") && !value.contains(" ")
    }
    private static func unique<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>(); return values.filter { seen.insert($0).inserted }
    }
    private static func kindForTag(_ tag: String) -> EventKind {
        switch tag {
        case "RESI", "EMIG", "IMMI": return .residence
        case "EDUC", "GRAD": return .education
        case "OCCU", "RETI": return .work
        case "MARR": return .marriage
        default: return .other
        }
    }
    private static func titleForTag(_ tag: String) -> String {
        switch tag {
        case "RESI": return "Место жительства"; case "EDUC": return "Образование"; case "GRAD": return "Окончание учёбы"
        case "OCCU": return "Работа"; case "MARR": return "Свадьба"; case "DIV": return "Развод"; case "ENGA": return "Помолвка"
        case "ANUL": return "Аннулирование брака"; case "EMIG": return "Эмиграция"; case "IMMI": return "Иммиграция"
        case "BURI": return "Захоронение"; case "CREM": return "Кремация"; case "BAPM", "CHR": return "Крещение"
        case "RETI": return "Выход на пенсию"; case "CENS": return "Перепись"; case "NATU": return "Гражданство"; case "ADOP": return "Усыновление"
        default: return "Событие"
        }
    }
    private static func interchangeDate(_ input: String) -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
        let iso = value.components(separatedBy: "-")
        let dotted = value.components(separatedBy: ".")
        var parts: [String] = []
        if iso.count == 3 && iso[0].count == 4 { parts = [iso[2], iso[1], iso[0]] }
        if dotted.count == 3 && dotted[2].count == 4 { parts = dotted }
        if parts.count == 3, let day = Int(parts[0]), let month = Int(parts[1]), let year = Int(parts[2]), (1...31).contains(day), (1...12).contains(month), year > 0 { return "\(day) \(months[month - 1]) \(year)" }
        if value.range(of: #"^(?:(?:ABT|CAL|EST|BEF|AFT|BET|AND|FROM|TO) )?(?:\d{1,2} )?(?:(?:JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC) )?\d{3,4}(?: BC)?$"#, options: .regularExpression) != nil { return value }
        if value.hasPrefix("("), value.hasSuffix(")") { return value }
        return "(" + value.replacingOccurrences(of: "\n", with: " ") + ")"
    }
}
