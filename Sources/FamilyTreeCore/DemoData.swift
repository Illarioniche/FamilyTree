import Foundation

public extension FamilyProject {
    /// Fictional people and events; deterministic identifiers keep previews and tests repeatable.
    static var demo: FamilyProject {
        func id(_ number: Int) -> UUID {
            UUID(uuidString: "00000000-0000-4000-8000-" + String(format: "%012d", number))!
        }
        let people = [
            Person(id: id(1), givenName: "Николай", patronymic: "Иванович", familyName: "Волков", gender: .male,
                   birthDate: "1927", deathDate: "1998", isDeceased: true, birthPlace: "Суздаль", occupation: "Столяр",
                   biography: "Вырос в Суздале и всю жизнь работал с деревом. В семейном доме до сих пор стоит буфет, который Николай сделал к свадьбе. Летом учил внуков мастерить скворечники и различать деревья по листьям."),
            Person(id: id(2), givenName: "Анна", patronymic: "Михайловна", familyName: "Волкова", maidenName: "Лебедева", gender: .female,
                   birthDate: "1930", deathDate: "2013", isDeceased: true, birthPlace: "Владимир", occupation: "Учительница",
                   biography: "Преподавала русский язык и литературу. Собирала семейные письма, подписывала фотографии и записывала рассказы старших. Её тетрадь с воспоминаниями стала началом семейного архива.", isFavorite: true),
            Person(id: id(3), givenName: "Сергей", patronymic: "Николаевич", familyName: "Волков", gender: .male,
                   birthDate: "1956-04-18", birthPlace: "Владимир", occupation: "Инженер",
                   biography: "После института поселился в Ярославле. Работал инженером, а в свободное время фотографировал города Золотого кольца. В семье отвечает за большой альбом поездок и традицию собираться вместе в августе."),
            Person(id: id(4), givenName: "Ирина", patronymic: "Викторовна", familyName: "Волкова", maidenName: "Петрова", gender: .female,
                   birthDate: "1958-09-02", birthPlace: "Кострома", occupation: "Библиотекарь",
                   biography: "Познакомилась с Сергеем на студенческой экскурсии. Долгие годы работала в библиотеке и организовывала встречи с писателями. Помнит семейные истории в деталях и хранит рецепты своей мамы Лидии."),
            Person(id: id(5), givenName: "Виктор", patronymic: "Андреевич", familyName: "Петров", gender: .male,
                   birthDate: "около 1932", deathDate: "2005", isDeceased: true, birthPlace: "Костромская область", occupation: "Агроном",
                   biography: "Точный день рождения пока не найден в документах. Виктор работал агрономом и любил садоводство. Посаженные им яблони каждую осень собирали за одним столом детей, внуков и соседей."),
            Person(id: id(6), givenName: "Лидия", patronymic: "Павловна", familyName: "Петрова", maidenName: "Орлова", gender: .female,
                   birthDate: "1935", deathDate: "2019", isDeceased: true, birthPlace: "Кострома", occupation: "Медсестра",
                   biography: "Работала в районной больнице. Любила вышивку и выращивала цветы у дома. Каждому внуку дарила вышитую салфетку с инициалами; несколько таких вещей сохранились в семейной коллекции."),
            Person(id: id(7), givenName: "Елена", patronymic: "Сергеевна", familyName: "Волкова", gender: .female,
                   birthDate: "1988-06-12", birthPlace: "Ярославль", occupation: "Архитектор",
                   biography: "Собирает историю семьи по письмам, фотографиям и разговорам с близкими. Любит старые дома и зарисовки в путешествиях. Мечтает однажды устроить семейную выставку, где у каждой фотографии будет своя история.", isFavorite: true),
            Person(id: id(8), givenName: "Алексей", patronymic: "Дмитриевич", familyName: "Соколов", gender: .male,
                   birthDate: "1986-11-24", birthPlace: "Рыбинск", occupation: "Программист",
                   biography: "Познакомился с Еленой в походе по Карелии. Помогает оцифровывать семейные снимки и записывать рассказы родственников. Вместе с детьми строит модели кораблей и планирует маршруты летних поездок."),
            Person(id: id(9), givenName: "Михаил", patronymic: "Сергеевич", familyName: "Волков", gender: .male,
                   birthDate: "1991-02-08", birthPlace: "Ярославль", occupation: "Музыкант",
                   biography: "Младший брат Елены. Играет на гитаре и записывает музыку. На семейных встречах первым достаёт старые песни и любит пересказывать истории детства, каждый раз добавляя новые подробности."),
            Person(id: id(10), givenName: "Софья", patronymic: "Алексеевна", familyName: "Соколова", gender: .female,
                   birthDate: "2014-03-07", birthPlace: "Москва", occupation: "Школьница",
                   biography: "Любит рисовать и задавать бабушке Ирине вопросы о её детстве. Придумала отмечать семейные места на большой карте. Первой иллюстрацией для семейного альбома стал дом прадедушки Николая."),
            Person(id: id(11), givenName: "Артём", patronymic: "Алексеевич", familyName: "Соколов", gender: .male,
                   birthDate: "2018-08-19", birthPlace: "Москва",
                   biography: "Младший в семейной ветви. Любит поезда, конструкторы и истории дедушки Сергея о путешествиях. На общих фотографиях обычно держит любимый деревянный паровоз."),
            Person(id: id(12), givenName: "Павел", patronymic: "Николаевич", familyName: "Волков", gender: .male,
                   birthDate: "1960-01-30", birthPlace: "Владимир", occupation: "Реставратор",
                   biography: "Младший брат Сергея. Унаследовал от отца любовь к столярному делу и занялся реставрацией мебели. Бережно восстановил семейный буфет и нашёл под нижним ящиком старую записку Николая.")
        ]
        let links: [(Int, Int, RelationshipKind)] = [
            (1, 2, .partner), (5, 6, .partner), (3, 4, .partner), (7, 8, .partner),
            (1, 3, .parent), (2, 3, .parent), (1, 12, .parent), (2, 12, .parent),
            (5, 4, .parent), (6, 4, .parent), (3, 7, .parent), (4, 7, .parent),
            (3, 9, .parent), (4, 9, .parent), (7, 10, .parent), (8, 10, .parent),
            (7, 11, .parent), (8, 11, .parent)
        ]
        let relationships = links.enumerated().map { index, link in
            Relationship(id: id(1_001 + index), fromID: id(link.0), toID: id(link.1), kind: link.2)
        }
        var events = people.enumerated().map { index, person in
            FamilyEvent(id: id(2_001 + index), personID: person.id, kind: .birth, title: "Рождение", date: person.birthDate, place: person.birthPlace)
        }
        events += [
            FamilyEvent(id: id(2_101), personID: id(1), kind: .marriage, title: "Свадьба Николая и Анны", date: "1953", place: "Владимир", notes: "В семейном альбоме сохранилась групповая фотография у дома."),
            FamilyEvent(id: id(2_102), personID: id(3), kind: .education, title: "Окончание политехнического института", date: "1978", place: "Ярославль"),
            FamilyEvent(id: id(2_103), personID: id(4), kind: .marriage, title: "Свадьба Ирины и Сергея", date: "1982-07-17", place: "Кострома", notes: "Праздновали в саду у родителей Ирины."),
            FamilyEvent(id: id(2_104), personID: id(7), kind: .education, title: "Диплом архитектора", date: "2011", place: "Москва", notes: "Дипломный проект был посвящён восстановлению исторического квартала."),
            FamilyEvent(id: id(2_105), personID: id(7), kind: .marriage, title: "Свадьба Елены и Алексея", date: "2012-08-25", place: "Ярославль", notes: "На церемонии собрались три поколения семьи."),
            FamilyEvent(id: id(2_106), personID: id(7), kind: .residence, title: "Новый дом в Москве", date: "2013", place: "Москва"),
            FamilyEvent(id: id(2_107), personID: id(7), kind: .other, title: "Начало семейного архива", date: "2022", notes: "Елена разобрала тетради Анны Михайловны и начала подписывать отсканированные фотографии."),
            FamilyEvent(id: id(2_108), personID: id(12), kind: .work, title: "Восстановление семейного буфета", date: "2020", place: "Владимир")
        ]
        var project = FamilyProject(id: id(9_000), title: "Семья Волковых", rootPersonID: id(7), people: people, relationships: relationships, events: events)
        project.createdAt = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01 UTC
        project.modifiedAt = project.createdAt
        return project
    }
}
