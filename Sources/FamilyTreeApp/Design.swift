import SwiftUI
import AppKit
import FamilyTreeCore

enum Palette {
    static let accent = Color(nsColor: NSColor(name: "RodnyeAccent") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.58, green: 0.75, blue: 0.64, alpha: 1)
            : NSColor(red: 0.29, green: 0.45, blue: 0.36, alpha: 1)
    })
    static let canvas = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.12, green: 0.14, blue: 0.13, alpha: 1)
            : NSColor(red: 0.97, green: 0.975, blue: 0.96, alpha: 1)
    })
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let divider = Color.primary.opacity(0.07)
    static func avatar(_ gender: Gender) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            switch gender {
            case .female: return dark ? NSColor(red: 0.85, green: 0.66, blue: 0.59, alpha: 1) : NSColor(red: 0.64, green: 0.46, blue: 0.40, alpha: 1)
            case .male: return dark ? NSColor(red: 0.62, green: 0.77, blue: 0.84, alpha: 1) : NSColor(red: 0.38, green: 0.51, blue: 0.58, alpha: 1)
            case .unspecified: return dark ? NSColor(red: 0.58, green: 0.75, blue: 0.64, alpha: 1) : NSColor(red: 0.29, green: 0.45, blue: 0.36, alpha: 1)
            }
        })
    }
}

struct PersonAvatar: View {
    let person: Person
    let project: FamilyProject
    var size: CGFloat = 44
    var body: some View {
        Group {
            if let id = person.photoID, let item = project.attachments.first(where: { $0.id == id }),
               let image = NSImage(data: item.data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(Palette.avatar(person.gender).opacity(0.12))
                    Text(person.initials).font(.system(size: size * 0.32, weight: .medium, design: .rounded))
                        .foregroundStyle(Palette.avatar(person.gender))
                }
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .overlay(Circle().strokeBorder(.primary.opacity(0.05), lineWidth: 1))
        .accessibilityLabel(person.fullName)
    }
}

struct SectionCaption: View {
    let title: String
    var body: some View {
        Text(title.uppercased()).font(.system(size: 10, weight: .semibold))
            .tracking(1.4).foregroundStyle(.secondary)
    }
}

struct EmptyCollectionView: View {
    let symbol: String
    let title: String
    let subtitle: String
    var actionTitle: String?
    var action: (() -> Void)?
    var body: some View {
        VStack(spacing: 15) {
            Image(systemName: symbol).font(.system(size: 38, weight: .ultraLight))
                .foregroundStyle(Palette.accent).frame(width: 84, height: 84)
                .background(Palette.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 24))
            Text(title).font(.system(size: 22, weight: .medium, design: .rounded))
            Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 310)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent).tint(Palette.accent)
                    .padding(.top, 5)
            }
        }
        .padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SmallIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 25, height: 25) }
            .buttonStyle(.borderless).help(help).accessibilityLabel(help)
    }
}
