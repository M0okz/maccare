import SwiftUI

struct SpaceView: View {
    @ObservedObject var model: SpaceModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(FileStoragePreferences.Key.view) private var mode = SpaceDisplayMode.map
    @State private var mapHighlightedPath: String?
    @State private var removal: RemovalRequest?
    @State private var infoChild: SpaceChild?
    @State private var showMeasurementInfo = false
    @State private var volumeUsage: SpaceVolumeUsage?

    private struct RemovalRequest {
        let child: SpaceChild
        let direct: Bool
    }

    var body: some View {
        ZStack {
            CategoryBackground(section: .space)
            if model.isLoading { progress }
            else if model.hasMeasured { explorer }
            else { introduction }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: model.isLoading)
        .onAppear { volumeUsage = SpaceVolumeUsage.read(at: model.root.path) }
        .onChange(of: model.root.path) { path in volumeUsage = SpaceVolumeUsage.read(at: path) }
        .onChange(of: model.lastMeasuredAt) { date in
            if date != nil { volumeUsage = SpaceVolumeUsage.read(at: model.root.path) }
        }
        .alert("Retirer cet élément ?", isPresented: Binding(
            get: { removal != nil }, set: { if !$0 { removal = nil } }
        ), presenting: removal) { request in
            Button(request.direct ? "Supprimer définitivement" : "Déplacer vers la corbeille", role: .destructive) {
                model.trash(request.child, directOverride: request.direct)
                removal = nil
            }
            Button("Annuler", role: .cancel) { removal = nil }
        } message: { request in
            Text("« \(request.child.name) » · \(request.child.sizeLabel). " +
                 (request.direct ? "La suppression est définitive." : "L’élément sera déplacé vers la corbeille."))
        }
    }

    private var introduction: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ScrollView {
                    HStack(spacing: 48) {
                        artwork.frame(width: 280, height: 300)
                        VStack(alignment: .leading, spacing: 22) {
                            Text("Espace disque").font(.system(size: 44)).accessibilityAddTraits(.isHeader)
                            Text("Découvrez ce qui occupe votre stockage. Choisissez un disque ou un dossier, puis explorez sa carte et sa liste, du plus volumineux au plus petit.")
                                .font(.system(size: 18)).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            locationMenu
                        }.frame(maxWidth: 450, alignment: .leading)
                    }.padding(36).frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
            }
            OverviewActionFooter(caption: "Mesure seule. Aucun élément n’est sélectionné pour suppression.",
                                 message: model.statusMessage) {
                Button("Explorer") { model.setRoot(model.root) }
                    .buttonStyle(CircularOverviewActionStyle(tint: ModuleColor.space))
                    .accessibilityLabel(model.isDiskRoot ? "Explorer ce disque" : "Explorer ce dossier")
            }
        }
    }

    /// Le menu natif actualise les volumes avant son ouverture, y compris au clavier.
    private var locationMenu: some View {
        VolumeLocationMenu(model: model)
            .padding(.horizontal, 14).frame(width: 300, height: 44)
            .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.hairline))
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 55)
                .fill(LinearGradient(colors: [ModuleColor.space.shade(0.2), Theme.accent.shade(-0.4)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 55).strokeBorder(Color.white.opacity(0.25)))
                .frame(width: 235, height: 235).rotationEffect(.degrees(-8))
            Image(systemName: "chart.pie.fill").font(.system(size: 120)).foregroundStyle(.white)
            Image(systemName: "folder.fill").font(.system(size: 42)).foregroundStyle(Theme.accentInk)
                .padding(16).background(Theme.window, in: Circle()).offset(x: 100, y: 95)
        }.accessibilityHidden(true)
    }

    private var progress: some View {
        VStack(spacing: 18) {
            Text("Espace disque").font(AppFont.body.weight(.semibold)).foregroundStyle(Theme.muted)
            Spacer(minLength: 12)
            StorageScanArtwork()
            Text(model.isDiskRoot && !model.canGoUp ? "Visualisation de votre stockage…" : "Exploration de votre dossier…")
                .font(.system(size: 32, weight: .regular)).multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
            Text(model.canGoUp ? model.currentPath : model.root.name)
                .font(.system(size: 17)).foregroundStyle(Theme.muted).lineLimit(2).truncationMode(.middle)
            HStack(spacing: 32) {
                scanMetric(model.liveEntries.formatted(), label: "entrées lues")
                scanMetric(humanSize(model.liveBytes), label: "données mesurées")
            }.padding(.top, 6)
            Spacer(minLength: 12)
            Button { model.cancelMeasurement() } label: {
                ZStack {
                    Circle().fill(LinearGradient(colors: [Theme.accent, Theme.accent.shade(-0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 82, height: 82).shadow(color: Theme.accent.opacity(0.4), radius: 18)
                    ScanActivityRing(lineWidth: 4).frame(width: 94, height: 94)
                    Text("Arrêter").font(AppFont.body.weight(.semibold)).foregroundStyle(.white)
                }.frame(width: 104, height: 104)
            }.buttonStyle(.plain).accessibilityLabel("Arrêter la mesure")
            Text("Analyse seule. Vous pourrez examiner les résultats avant toute action.")
                .font(AppFont.secondary).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }.padding(.horizontal, 32).padding(.top, 18).padding(.bottom, 18).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scanMetric(_ value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 21, weight: .medium)).monospacedDigit()
            Text(label).font(AppFont.caption).foregroundStyle(Theme.muted)
        }.accessibilityElement(children: .combine)
    }

    private var explorer: some View {
        GeometryReader { container in
        let contentWidth = max(0, container.size.width - 48)
        let storageWidth = mode == .map && contentWidth >= 700 ? listColumnWidth(in: contentWidth) : min(390, contentWidth)
        VStack(alignment: .leading, spacing: 14) {
            header
            breadcrumb
            if model.children.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Text("Aucun élément à afficher").font(AppFont.section)
                    Text("Choisissez un autre dossier ou actualisez la mesure.").font(AppFont.body).foregroundStyle(Theme.muted)
                    Spacer()
                }.frame(maxWidth: .infinity)
            } else {
                GeometryReader { geometry in
                    if mode == .list {
                        listPanel.frame(width: geometry.size.width, height: geometry.size.height)
                    } else if geometry.size.width >= 700 {
                        HStack(spacing: 20) {
                            listPanel.frame(width: listColumnWidth(in: geometry.size.width))
                            map.frame(maxWidth: .infinity)
                        }
                    } else {
                        map
                    }
                }
            }
            selectionInfo.frame(height: 76, alignment: .leading)
            messages
            storageFooter(columnWidth: storageWidth)
        }
        .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 16)
        }
    }

    private func listColumnWidth(in availableWidth: CGFloat) -> CGFloat {
        min(390, max(300, availableWidth * 0.36))
    }

    private var header: some View {
        HStack(spacing: 18) {
            Button { model.returnToStart() } label: { Label("Changer d’emplacement", systemImage: "arrow.uturn.backward") }
                .buttonStyle(.plain).font(AppFont.secondary)
            Spacer(minLength: 12)
            Text("Espace disque").font(AppFont.body.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            Button { model.load() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(SecondaryActionButtonStyle()).accessibilityLabel("Actualiser la mesure").help("Actualiser la mesure")
            Picker("Présentation", selection: $mode) {
                Text("Carte").tag(SpaceDisplayMode.map)
                Text("Liste").tag(SpaceDisplayMode.list)
            }.pickerStyle(.segmented).frame(width: 150).labelsHidden()
                .accessibilityLabel("Présentation de l’espace disque")
        }
    }

    private var listPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: model.canGoUp || !model.isDiskRoot ? "folder.fill" : "internaldrive.fill")
                    .font(.system(size: 28)).foregroundStyle(Theme.accentInk).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.crumbs.last?.name ?? model.root.name).font(AppFont.body.weight(.semibold)).lineLimit(2)
                    Text("\(model.children.count) \(pl(model.children.count, "élément")) · \(model.hasPartial ? "au moins " : "")\(humanSize(model.totalSize))")
                        .font(AppFont.secondary).monospacedDigit().foregroundStyle(Theme.muted)
                }
            }.padding(.horizontal, 16).padding(.top, 16)
            itemList
        }.background(Theme.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 18))
    }

    private func storageFooter(columnWidth: CGFloat) -> some View {
        HStack(spacing: 18) {
            if let usage = volumeUsage {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(usage.name).font(AppFont.caption.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 12)
                        Text("\(humanSize(usage.used)) utilisés sur \(humanSize(usage.total))")
                            .font(AppFont.caption).foregroundStyle(Theme.muted).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.85)
                    }
                    ProgressView(value: Double(usage.used), total: Double(max(usage.total, 1)))
                        .accessibilityLabel("Occupation du volume \(usage.name)")
                }.frame(width: columnWidth, alignment: .leading)
            }
            Spacer(minLength: 12)
            if let date = model.lastMeasuredAt {
                Label("Mesuré à \(date.formatted(date: .omitted, time: .shortened))", systemImage: "checkmark.circle.fill")
                    .font(AppFont.caption).foregroundStyle(Theme.muted)
            }
        }.padding(.top, 4)
    }

    private var breadcrumb: some View {
        HStack(spacing: 12) {
            Button { model.goUp() } label: { Label("Parent", systemImage: "arrow.up") }
                .buttonStyle(SecondaryActionButtonStyle()).disabled(!model.canGoUp)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(model.crumbs.enumerated()), id: \.offset) { index, crumb in
                        if index > 0 {
                            Image(systemName: "chevron.right").foregroundStyle(Theme.muted).accessibilityHidden(true)
                        }
                        Button(crumb.name) { model.goTo(path: crumb.path) }
                            .buttonStyle(.link)
                            .disabled(index == model.crumbs.count - 1)
                    }
                }.font(AppFont.secondary)
            }
        }.padding(10).background(Theme.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private var map: some View {
        VStack(spacing: 8) {
            SpaceBubblesView(model: model, onMapHighlight: { mapHighlightedPath = $0 }, onRequestRemoval: requestRemoval)
            Text("Double-cliquez sur une bulle pour ouvrir le dossier")
                .font(AppFont.caption).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }
    }

    private var itemList: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.children) { child in
                        row(child).id(child.id)
                        if child.id != model.children.last?.id { Divider().overlay(Theme.hairline) }
                    }
                }.background(Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
            }
            .onChange(of: mapHighlightedPath) { path in
                if let path { reader.scrollTo(path, anchor: .center) }
            }
        }
    }

    private func row(_ child: SpaceChild) -> some View {
        return HStack(spacing: 2) {
            Button { infoChild = child } label: {
                Image(systemName: "info.circle").font(.system(size: 15)).foregroundStyle(Theme.muted)
                    .frame(width: 30, height: 40).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Informations sur \(child.name)")
                .help(model.canRemove(child) ? "Informations sur cet élément" : "Pourquoi cet élément est-il en lecture seule ?")
                .popover(isPresented: Binding(get: { infoChild?.id == child.id }, set: { if !$0 { infoChild = nil } }), arrowEdge: .leading) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(child.name).font(AppFont.emphasis.weight(.semibold))
                        Text(model.canRemove(child)
                             ? "Vous pouvez explorer cet élément ou afficher son emplacement. Tout retrait reste soumis aux protections de MacCare et à une confirmation."
                             : "Cet emplacement est en lecture seule dans MacCare. Les dossiers de base du Mac et les éléments situés hors de votre dossier personnel ne peuvent pas être retirés ici. Vous pouvez continuer à les explorer.")
                            .font(AppFont.body).fixedSize(horizontal: false, vertical: true)
                        Text(child.path).font(AppFont.caption).foregroundStyle(Theme.muted).textSelection(.enabled)
                    }.padding(20).frame(width: 340)
                }
            rowButton(child)
        }
        .padding(.leading, 6)
    }

    private func rowButton(_ child: SpaceChild) -> some View {
        let highlighted = (model.highlightedPath ?? model.selectedPath) == child.id
        return Button {
            if child.is_dir { model.open(child) } else { model.select(child) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: child.is_dir ? "folder.fill" : "doc.fill")
                    .font(.system(size: 20)).foregroundStyle(Theme.accentInk).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(child.name).font(AppFont.body.weight(.medium)).lineLimit(1).truncationMode(.middle)
                    if !child.measured {
                        Text(child.size_bytes == 0 ? "Non mesuré" : "Mesure partielle")
                            .font(AppFont.caption).foregroundStyle(Theme.warn)
                    }
                }
                Spacer(minLength: 8)
                Text(child.sizeLabel).font(AppFont.secondary.weight(.semibold)).monospacedDigit()
                if child.is_dir { Image(systemName: "chevron.right").foregroundStyle(Theme.muted).accessibilityHidden(true) }
            }
            .foregroundStyle(Theme.fg).padding(.horizontal, 12).padding(.vertical, 12)
            .background(highlighted ? Theme.accent.opacity(0.22) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover in
            model.highlight(hover ? child.id : nil, from: .row(child.id))
        }
        .accessibilityLabel("\(child.name), \(child.sizeLabel)")
        .accessibilityValue(model.highlightedPath == child.id ? "Survolé" : model.selectedPath == child.id ? "Sélectionné" : "")
        .accessibilityHint(child.is_dir ? "Ouvre ce dossier" : "Affiche les informations du fichier")
        .help("\(child.name) · \(child.sizeLabel)")
        .contextMenu {
            Button("Afficher dans le Finder") { model.revealInFinder(child) }
            if model.canRemove(child) { Button(model.directDeleteLabel, role: .destructive) { requestRemoval(child) } }
        }
    }

    private var focusedChild: SpaceChild? {
        let path = model.highlightedPath ?? model.selectedPath
        return model.children.first { $0.id == path }
    }

    @ViewBuilder private var selectionInfo: some View {
        if let child = focusedChild {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(child.name).font(AppFont.body.weight(.semibold)).lineLimit(1).textSelection(.enabled)
                    Text(child.path).font(AppFont.caption).foregroundStyle(Theme.muted).lineLimit(2).truncationMode(.middle)
                }
                Spacer()
                Text(child.sizeLabel).font(AppFont.body).monospacedDigit()
                Button("Afficher dans le Finder") { model.revealInFinder(child) }.buttonStyle(SecondaryActionButtonStyle())
            }.padding(12).background(Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        } else if mode == .list {
            Text("Cliquez sur un dossier pour l’ouvrir, ou sur un fichier pour afficher ses informations.")
                .font(AppFont.secondary).foregroundStyle(Theme.muted)
        } else {
            Color.clear.allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    @ViewBuilder private var messages: some View {
        HStack(spacing: 12) {
            if model.hasPartial || model.isDiskRoot {
                Button { showMeasurementInfo.toggle() } label: {
                    Label(model.hasPartial ? "Certaines tailles sont partielles" : "À propos de cette mesure", systemImage: "info.circle")
                        .font(AppFont.caption).foregroundStyle(model.hasPartial ? Theme.warn : Theme.muted)
                }.buttonStyle(.plain).popover(isPresented: $showMeasurementInfo) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Périmètre de la mesure").font(AppFont.emphasis.weight(.semibold))
                        Text("Les tailles partielles sont des minimums. Les zones protégées, les instantanés APFS et les autres volumes ne sont pas tous comptabilisés ; le total peut différer de l’occupation du volume affichée par macOS.")
                            .font(AppFont.body).fixedSize(horizontal: false, vertical: true)
                    }.padding(20).frame(width: 360)
                }
            }
            Spacer()
        }
        if let report = model.lastReport {
            Text(report.summary).font(AppFont.secondary).foregroundStyle(report.needsAttention ? Theme.warn : Theme.muted)
        }
        if let message = model.statusMessage {
            Text(message).font(AppFont.secondary).foregroundStyle(Theme.warn)
        }
    }

    private func requestRemoval(_ child: SpaceChild) {
        removal = RemovalRequest(child: child, direct: model.directDelete)
    }
}
