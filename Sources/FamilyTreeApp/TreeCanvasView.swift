import SwiftUI
import AppKit
import FamilyTreeCore

struct TreeCanvasView: View {
    let project: FamilyProject
    @Binding var selection: UUID?
    let onAddRelative: (UUID) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var mode: TreeScopeMode
    @State private var focusID: UUID?
    @State private var camera = TreeViewport()
    @State private var dragStart: TreeViewport?
    @State private var initialized = false
    @State private var framingRequest = 0
    @State private var chooserPresented = false
    @State private var scopeInfoPresented = false
    @State private var focusHistory: [BranchHistoryEntry] = []
    private let sage = Palette.accent

    init(project: FamilyProject, selection: Binding<UUID?>, onAddRelative: @escaping (UUID) -> Void, initialMode: TreeScopeMode? = nil) {
        self.project = project; self._selection = selection; self.onAddRelative = onAddRelative
        _focusID = State(initialValue: selection.wrappedValue ?? project.rootPersonID ?? project.people.first?.id)
        _mode = State(initialValue: initialMode ?? .close)
    }

    var body: some View {
        let scoped = TreeScope.make(project: project, focusID: focusID, mode: mode)
        let layout = TreeLayout.make(project: scoped.project)
        VStack(spacing: 0) {
            if !project.people.isEmpty { navigationBar(scoped) }
            GeometryReader { geometry in
                ZStack {
                    canvasBackground
                    if project.people.isEmpty {
                        emptyState
                    } else {
                        drawing(layout, scope: scoped)
                            .scaleEffect(camera.scale, anchor: .topLeading)
                            .frame(width: layout.width * camera.scale, height: layout.height * camera.scale, alignment: .topLeading)
                            .position(
                                x: geometry.size.width / 2 + (layout.width / 2 - camera.centerX) * camera.scale,
                                y: geometry.size.height / 2 + (layout.height / 2 - camera.centerY) * camera.scale
                            )
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .contentShape(Rectangle())
                .clipped()
                .simultaneousGesture(DragGesture(minimumDistance: 4).onChanged { value in
                    guard !project.people.isEmpty else { return }
                    if dragStart == nil { dragStart = camera }
                    if var start = dragStart {
                        start.pan(screenDX: value.translation.width, screenDY: value.translation.height)
                        camera = start
                    }
                }.onEnded { _ in dragStart = nil })
                .background {
                    TreeInputSurface(onPan: { dx, dy in
                        camera.pan(screenDX: dx, screenDY: dy)
                    }, onZoom: { factor, point in
                        camera.zoom(to: camera.scale * factor, anchorX: point.x, anchorY: point.y,
                                    viewportWidth: geometry.size.width, viewportHeight: geometry.size.height)
                    })
                }
                .overlay(alignment: .bottomLeading) {
                    if !project.people.isEmpty {
                        zoomControls(layout: layout, size: geometry.size).padding(18)
                    }
                }
                .onAppear { prepareCamera(layout, size: geometry.size); initialized = true }
                .onChange(of: layout) { _, new in
                    if initialized { prepareCamera(new, size: geometry.size) }
                }
                .onChange(of: framingRequest) { _, _ in prepareCamera(layout, size: geometry.size) }
                .onChange(of: mode) { _, _ in prepareCamera(layout, size: geometry.size) }
                .onChange(of: focusID) { _, _ in prepareCamera(layout, size: geometry.size) }
                .onChange(of: selection) { _, selected in
                    guard let selected, project.person(selected) != nil else { return }
                    if let node = layout.node(selected) {
                        let screen = camera.screenPoint(worldX: node.x, worldY: node.y, viewportWidth: geometry.size.width, viewportHeight: geometry.size.height)
                        let halfWidth = TreeLayout.cardWidth * camera.scale / 2
                        let halfHeight = TreeLayout.cardHeight * camera.scale / 2
                        if screen.x + halfWidth < 0 || screen.x - halfWidth > geometry.size.width ||
                           screen.y + halfHeight < 0 || screen.y - halfHeight > geometry.size.height {
                            withAnimation(.easeOut(duration: 0.2)) { camera.focus(x: node.x, y: node.y) }
                        }
                    } else {
                        navigate(to: selected)
                    }
                }
                .onChange(of: project.id) { _, _ in
                    focusHistory.removeAll()
                    focusID = selection ?? project.rootPersonID ?? project.people.first?.id
                    mode = .close
                }
                .onChange(of: project.people.map(\.id)) { _, ids in
                    let valid = Set(ids)
                    focusHistory.removeAll { !valid.contains($0.id) }
                    if let current = focusID, !valid.contains(current) {
                        focusID = selection.flatMap { valid.contains($0) ? $0 : nil } ?? project.rootPersonID ?? ids.first
                    }
                }
                .onChange(of: project.rootPersonID) { _, root in
                    if let root { navigate(to: root) }
                }
                .accessibilityIdentifier("familyTreeCanvas")
            }
        }
    }

    private func navigationBar(_ scope: TreeScopeResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Picker("Вид дерева", selection: $mode) {
                    ForEach(TreeScopeMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 360)
                Spacer(minLength: 4)
                Button { scopeInfoPresented.toggle() } label: {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain).help("Кто входит в этот вид дерева")
                .accessibilityLabel("Состав вида «\(mode.title)»")
                .popover(isPresented: $scopeInfoPresented, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(mode.title).font(.system(size: 14, weight: .semibold))
                        Text(scopeExplanation).font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }.padding(18).frame(width: 300, alignment: .leading)
                }
            }
            HStack(spacing: 8) {
                Button {
                    while let previous = focusHistory.popLast() {
                        guard project.person(previous.id) != nil else { continue }
                        mode = previous.mode
                        focusID = previous.id; selection = previous.id
                        break
                    }
                } label: { Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold)) }
                .buttonStyle(.plain).disabled(focusHistory.isEmpty).help("Вернуться к предыдущей ветви")
                Button { chooserPresented = true } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "scope").foregroundStyle(sage)
                        Text(project.person(scope.focusID)?.shortName ?? "Выбрать человека")
                            .font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
                    }
                }.buttonStyle(.plain).help("Выбрать центр дерева")
                .popover(isPresented: $chooserPresented, arrowEdge: .bottom) {
                    TreeFocusChooser(project: project, current: scope.focusID) { id in
                        chooserPresented = false; navigate(to: id)
                    }
                }
                if let selected = selection, selected != scope.focusID {
                    Button("К выбранному") { navigate(to: selected) }
                        .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(sage)
                }
                Spacer(minLength: 6)
                Text(mode == .all ? "Все \(scope.totalPeopleCount) человек" : "Показано \(scope.project.people.count) из \(scope.totalPeopleCount)")
                    .font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                    .help("Виды дерева меняют только отображение. Все люди и связи остаются в файле.")
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .background(Palette.surface.opacity(0.6))
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.divider).frame(height: 1) }
    }

    private func navigate(to id: UUID, revealRelatives: Bool = false) {
        guard project.person(id) != nil else { return }
        let newMode: TreeScopeMode = mode == .all || revealRelatives ? .close : mode
        if let previous = focusID, previous != id || newMode != mode {
            focusHistory.append(BranchHistoryEntry(id: previous, mode: mode))
        }
        if focusHistory.count > 50 { focusHistory.removeFirst() }
        mode = newMode
        focusID = id; selection = id
        framingRequest += 1
    }

    private func prepareCamera(_ layout: TreeLayoutResult, size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        camera.frame(contentWidth: layout.width, contentHeight: layout.height,
                     viewportWidth: size.width, viewportHeight: max(1, size.height - 55),
                     minimumReadableScale: mode == .all ? 0 : 0.9)
        // A wide family is allowed to extend beyond the window. Keep its centre
        // person reachable instead of shrinking every card until labels disappear.
        if let id = focusID ?? selection ?? project.rootPersonID, let node = layout.node(id) {
            let screen = camera.screenPoint(worldX: node.x, worldY: node.y, viewportWidth: size.width, viewportHeight: size.height)
            if mode != .all {
                if layout.width * camera.scale > size.width {
                    let halfVisibleWidth = size.width / (2 * camera.scale)
                    camera.centerX = min(max(node.x, halfVisibleWidth), layout.width - halfVisibleWidth)
                }
                if screen.y < 70 || screen.y > size.height - 100 { camera.centerY = node.y }
            }
        }
    }

    private var canvasBackground: some View {
        ZStack {
            Palette.canvas
            Canvas { context, size in
                let color = colorScheme == .dark ? Color.white.opacity(0.07) : sage.opacity(0.13)
                for x in stride(from: 12.0, through: size.width, by: 24.0) {
                    for y in stride(from: 12.0, through: size.height, by: 24.0) {
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.4, height: 1.4)), with: .color(color))
                    }
                }
            }.accessibilityHidden(true)
        }
    }

    private func drawing(_ layout: TreeLayoutResult, scope: TreeScopeResult) -> some View {
        let people = scope.project.people.reduce(into: [UUID: Person]()) { $0[$1.id] = $1 }
        let connectors = TreeConnectors.make(layout: layout)
        let photos = scope.project.attachments.reduce(into: [UUID: Data]()) { if $1.isImage { $0[$1.id] = $1.data } }
        return ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for stroke in connectors.strokes {
                    let highlighted = selection.map { stroke.personIDs.contains($0) } ?? false
                    context.stroke(connectorPath(stroke.points),
                                   with: .color(sage.opacity(highlighted ? 0.8 : 0.38)),
                                   style: StrokeStyle(lineWidth: highlighted ? 1.8 : 1.3, lineCap: .round,
                                                      lineJoin: .round, dash: stroke.isDashed ? [5, 4] : []))
                }
                for junction in connectors.junctions {
                    let highlighted = selection.map { junction.personIDs.contains($0) } ?? false
                    context.fill(Path(ellipseIn: CGRect(x: junction.point.x - 2.2, y: junction.point.y - 2.2,
                                                       width: 4.4, height: 4.4)),
                                 with: .color(sage.opacity(highlighted ? 0.8 : 0.5)))
                }
            }.allowsHitTesting(false).accessibilityHidden(true)
            ForEach(layout.nodes) { node in
                if let person = people[node.id] {
                    TreePersonCard(person: person, photoData: person.photoID.flatMap { photos[$0] },
                                   isSelected: selection == person.id, isRoot: project.rootPersonID == person.id,
                                   isFocus: scope.focusID == person.id,
                                   hiddenRelativeCount: scope.hiddenRelativeCounts[person.id, default: 0],
                                   showBranch: { navigate(to: person.id, revealRelatives: true) },
                                   select: { selection = person.id },
                                   addRelative: { selection = person.id; onAddRelative(person.id) })
                    .frame(width: TreeLayout.cardWidth, height: TreeLayout.cardHeight)
                    .position(x: node.x, y: node.y)
                }
            }
        }.frame(width: layout.width, height: layout.height)
    }

    /// Round only the corners of the shared family buses, preserving their endpoints.
    private func connectorPath(_ points: [TreeConnectorPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: first.x, y: first.y))
        if points.count > 2 {
            for index in 1..<(points.count - 1) {
                let before = points[index - 1], corner = points[index], after = points[index + 1]
                let incoming = hypot(corner.x - before.x, corner.y - before.y)
                let outgoing = hypot(after.x - corner.x, after.y - corner.y)
                guard incoming > 0, outgoing > 0 else { continue }
                let radius = min(6, incoming / 2, outgoing / 2)
                let entry = CGPoint(x: corner.x + (before.x - corner.x) * radius / incoming,
                                    y: corner.y + (before.y - corner.y) * radius / incoming)
                let exit = CGPoint(x: corner.x + (after.x - corner.x) * radius / outgoing,
                                   y: corner.y + (after.y - corner.y) * radius / outgoing)
                path.addLine(to: entry)
                path.addQuadCurve(to: exit, control: CGPoint(x: corner.x, y: corner.y))
            }
        }
        if let last = points.last, points.count > 1 { path.addLine(to: CGPoint(x: last.x, y: last.y)) }
        return path
    }

    private var scopeExplanation: String {
        switch mode {
        case .close:
            return "Мама, папа, супруг или супруга, дети, братья, сёстры, бабушки и дедушки выбранного человека."
        case .relatives:
            return "Близкие, тёти и дяди, двоюродные бабушки и дедушки, двоюродные и троюродные братья и сёстры. Общие предки показаны, чтобы проследить родство."
        case .all:
            return "Все люди и связи из вашего семейного дерева. Двойной щелчок по человеку откроет его близких."
        }
    }

    private func zoomControls(layout: TreeLayoutResult, size: CGSize) -> some View {
        HStack(spacing: 3) {
            Button { zoom(to: camera.scale / 1.2, size: size) } label: { Image(systemName: "minus").frame(width: 27, height: 27).contentShape(Rectangle()) }
                .help("Уменьшить масштаб").accessibilityLabel("Уменьшить масштаб").accessibilityIdentifier("zoomOutButton")
            Button { zoom(to: 1, size: size) } label: {
                Text("\(Int((camera.scale * 100).rounded()))%")
                    .font(.system(size: 11, weight: .medium, design: .rounded)).monospacedDigit().frame(width: 41, height: 27).contentShape(Rectangle())
            }.help("Вернуть масштаб 100%").accessibilityLabel("Масштаб").accessibilityValue("\(Int((camera.scale * 100).rounded()))%").accessibilityIdentifier("zoomResetButton")
            Button { zoom(to: camera.scale * 1.2, size: size) } label: { Image(systemName: "plus").frame(width: 27, height: 27).contentShape(Rectangle()) }
                .help("Увеличить масштаб").accessibilityLabel("Увеличить масштаб").accessibilityIdentifier("zoomInButton")
            Divider().frame(height: 16).padding(.horizontal, 5)
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    camera.frame(contentWidth: layout.width, contentHeight: layout.height,
                                 viewportWidth: size.width, viewportHeight: max(1, size.height - 60))
                }
            } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 27, height: 27).contentShape(Rectangle()) }
                .help(mode == .all ? "Уместить всё дерево в окне" : "Уместить эту ветвь в окне").accessibilityIdentifier("zoomFitButton")
            Button {
                if let id = selection ?? focusID, let node = layout.node(id) {
                    withAnimation(.easeOut(duration: 0.2)) { camera.focus(x: node.x, y: node.y, readableScale: 1) }
                }
            } label: { Image(systemName: "scope").frame(width: 27, height: 27).contentShape(Rectangle()) }
                .help("Выбранный человек крупным планом").accessibilityIdentifier("zoomFocusButton")
        }
        .buttonStyle(.plain).foregroundStyle(sage)
        .padding(.horizontal, 7).padding(.vertical, 5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5).allowsHitTesting(false))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
    }

    private func zoom(to scale: Double, size: CGSize) {
        withAnimation(.easeOut(duration: 0.15)) {
            camera.zoom(to: scale, anchorX: size.width / 2, anchorY: size.height / 2,
                        viewportWidth: size.width, viewportHeight: size.height)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tree").font(.system(size: 48, weight: .ultraLight)).foregroundStyle(sage)
                .frame(width: 100, height: 100).background(sage.opacity(0.07), in: Circle())
            Text("Большая история начинается с одного человека")
                .font(.system(size: 21, weight: .medium, design: .serif)).multilineTextAlignment(.center)
            Text("Добавьте себя или близкого человека.\nПостепенно здесь появится история вашей семьи.")
                .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(4)
        }.padding(36).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct BranchHistoryEntry {
    var id: UUID
    var mode: TreeScopeMode
}

private struct TreeFocusChooser: View {
    let project: FamilyProject
    let current: UUID?
    let select: (UUID) -> Void
    @State private var query = ""
    private var matches: [Person] {
        project.people.filter { query.isEmpty || $0.fullName.localizedCaseInsensitiveContains(query) }
            .sorted { $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("С чьей истории начнём?").font(.system(size: 15, weight: .semibold))
            TextField("Имя или фамилия", text: $query).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(matches) { person in
                        Button { select(person.id) } label: {
                            HStack(spacing: 10) {
                                PersonAvatar(person: person, project: project, size: 30)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(person.fullName).font(.system(size: 12)).lineLimit(2)
                                    Text(person.lifespan).font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if person.id == current { Image(systemName: "checkmark").foregroundStyle(Palette.accent) }
                            }.padding(.vertical, 7).padding(.horizontal, 5).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    if matches.isEmpty { Text("Никого не нашли").font(.caption).foregroundStyle(.secondary).padding() }
                }
            }
        }.padding(18).frame(width: 325, height: 390)
    }
}

/// Scroll and pinch events are scoped to this canvas and window. A nil hit-test
/// leaves card buttons, dragging, menus and the inspector's native scrolling intact.
private struct TreeInputSurface: NSViewRepresentable {
    var onPan: (Double, Double) -> Void
    var onZoom: (Double, CGPoint) -> Void
    func makeNSView(context: Context) -> InputView {
        let view = InputView(); view.onPan = onPan; view.onZoom = onZoom; return view
    }
    func updateNSView(_ view: InputView, context: Context) { view.onPan = onPan; view.onZoom = onZoom }
    static func dismantleNSView(_ view: InputView, coordinator: ()) { view.stopMonitoring() }

    final class InputView: NSView {
        var onPan: ((Double, Double) -> Void)?
        var onZoom: ((Double, CGPoint) -> Void)?
        private var monitor: Any?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
                guard let self, let window = self.window, event.window === window,
                      window.attachedSheet == nil, !self.isHiddenOrHasHiddenAncestor else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else { return event }
                if event.type == .magnify {
                    self.onZoom?(max(0.5, 1 + event.magnification), point)
                } else if event.modifierFlags.intersection([.command, .control]).isEmpty {
                    let factor = event.hasPreciseScrollingDeltas ? 1.0 : 12.0
                    if event.modifierFlags.contains(.shift), abs(event.scrollingDeltaX) < 0.01 {
                        self.onPan?(event.scrollingDeltaY * factor, 0)
                    } else {
                        self.onPan?(event.scrollingDeltaX * factor, event.scrollingDeltaY * factor)
                    }
                } else {
                    self.onZoom?(exp(event.scrollingDeltaY * 0.012), point)
                }
                return nil
            }
        }
        func stopMonitoring() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
private struct TreePersonCard: View {
    let person: Person
    let photoData: Data?
    let isSelected: Bool
    let isRoot: Bool
    let isFocus: Bool
    let hiddenRelativeCount: Int
    let showBranch: () -> Void
    let select: () -> Void
    let addRelative: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    private let sage = Palette.accent

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .center, spacing: 9) {
                    VStack(spacing: 4) {
                        TreeAvatar(person: person, data: photoData)
                            .frame(width: 30, height: 30)
                        if isRoot || isFocus || person.isFavorite {
                            HStack(spacing: 4) {
                                if isRoot || isFocus {
                                    Image(systemName: isFocus ? "scope" : "house.fill")
                                        .foregroundStyle(sage.opacity(0.8))
                                }
                                if person.isFavorite {
                                    Image(systemName: "star.fill")
                                        .foregroundStyle(Color(red: 0.68, green: 0.51, blue: 0.28))
                                }
                            }.font(.system(size: 8))
                        }
                    }.frame(width: 30)
                    Text(person.fullName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(3).minimumScaleFactor(0.9)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(person.lifespan)
                    .font(.system(size: 10.5, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(cardColor, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(isSelected ? sage : Color.primary.opacity(isHovered ? 0.18 : 0.08), lineWidth: isSelected ? 1.8 : 0.7))
            .shadow(color: Color.black.opacity(isSelected ? 0.09 : 0.04), radius: isSelected ? 12 : 6, x: 0, y: isSelected ? 5 : 3)
            .contentShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .simultaneousGesture(TapGesture(count: 2).onEnded { showBranch() })
        .overlay(alignment: .topTrailing) {
            if hiddenRelativeCount > 0 {
                Button(action: showBranch) {
                    Text("+\(hiddenRelativeCount)")
                        .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(sage).padding(.horizontal, 7).frame(height: 22)
                        .background(cardColor, in: Capsule())
                        .overlay(Capsule().strokeBorder(sage.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain).offset(x: 6, y: -8)
                .help("За пределами ветви ещё родственников: \(hiddenRelativeCount). Открыть ветвь этого человека.")
                .accessibilityLabel("Открыть ветвь \(person.fullName), ещё родственников: \(hiddenRelativeCount)")
            }
        }
        .overlay(alignment: .bottom) {
            if isSelected {
                Button(action: addRelative) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 23, height: 23)
                        .background(sage, in: Circle())
                        .overlay(Circle().strokeBorder(cardColor, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .help("Добавить родственника")
                .accessibilityLabel("Добавить родственника для \(person.fullName)")
                .offset(y: 11)
            }
        }
        .contextMenu {
            Button("Показать ветвь", systemImage: "point.3.connected.trianglepath.dotted", action: showBranch)
            Button("Открыть карточку", systemImage: "person.text.rectangle", action: select)
            Button("Добавить родственника", systemImage: "person.badge.plus", action: addRelative)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(person.fullName), \(person.lifespan)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help("\(person.fullName)\n\(person.lifespan)")
    }

    private var cardColor: Color {
        colorScheme == .dark ? Color(red: 0.18, green: 0.20, blue: 0.19) : .white
    }
}

private struct TreeAvatar: View {
    let person: Person
    let data: Data?
    private var tint: Color {
        Palette.avatar(person.gender)
    }
    var body: some View {
        Group {
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(tint.opacity(0.12))
                    Text(person.initials).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(tint)
                }
            }
        }
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
