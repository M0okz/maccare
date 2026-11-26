import SwiftUI

struct SmartScanApplicationsView: View {
    @ObservedObject var model: SmartScanModel
    @Binding var detailID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showEmpty = false
    @State private var lastOpened: String?
    @FocusState private var focusedRow: String?
    @AccessibilityFocusState private var accessibleRow: String?
    @AccessibilityFocusState private var readingDetail: Bool

    var body: some View {
        let results = model.applications
        let detail = results.first { $0.id == detailID }
        ZStack(alignment: .topLeading) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.m) {
                    Text("Résultats par application").font(AppFont.pageTitle).accessibilityAddTraits(.isHeader)
                    Text("Choisissez une application pour examiner ses fichiers et l’effet d’un nettoyage.")
                        .font(AppFont.body).foregroundStyle(Theme.muted)
                    if let cleanup = model.cleanup {
                        SmartScanCleanupView(result: cleanup, busy: model.stage == .cleaning, retry: model.retryPendingCaches)
                    }
                    if let message = model.statusMessage {
                        Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.warn)
                    }
                    ForEach(results.filter { $0.count > 0 }) { result in row(result) }
                    let empty = results.filter { $0.count == 0 && $0.id != SmartScanAppProfile.other.id }
                    if !empty.isEmpty {
                        DisclosureGroup("Profils sans résultat dans cette analyse (\(empty.count))", isExpanded: $showEmpty) {
                            VStack(spacing: Space.s) { ForEach(empty) { result in row(result) } }
                                .padding(.top, Space.s)
                        }.font(AppFont.secondary)
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(detail != nil)
            .accessibilityHidden(detail != nil)
            .opacity(detail == nil ? 1 : 0)
            if let detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.m) {
                        HStack(spacing: Space.m) {
                            SmartScanProfileIcon(profile: detail.profile)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(detail.profile.name).font(AppFont.pageTitle).accessibilityAddTraits(.isHeader)
                                    .accessibilityFocused($readingDetail)
                                Text(summary(detail)).font(AppFont.secondary).foregroundStyle(Theme.muted)
                            }
                        }
                        if detail.count > 0 {
                            Text(detail.profile.impact).font(AppFont.body)
                        }
                        Label(detail.profile.protectedData, systemImage: detail.id == SmartScanAppProfile.other.id ? "folder" : "shield")
                            .font(AppFont.secondary).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                        if model.cleanup != nil {
                            Button("Consulter le bilan du nettoyage") { detailID = nil }.buttonStyle(.actionPill)
                        }
                        ForEach(detail.sections) { section in
                            VStack(alignment: .leading, spacing: Space.s) {
                                HStack {
                                    Text(section.category.title).font(AppFont.emphasis).accessibilityAddTraits(.isHeader)
                                    PillBadge(text: section.category.risk == .safe ? "Sûr" : "À revoir",
                                              kind: section.category.risk == .safe ? .safe : .review)
                                }
                                Text(section.category.summary).font(AppFont.secondary).foregroundStyle(Theme.muted)
                                VStack(spacing: 0) {
                                    ForEach(section.items) { item in
                                        if item.id != section.items.first?.id { Divider() }
                                        ItemRow(item: item, on: model.selection.contains(item.id)) { model.toggle(item) }
                                            .disabled(model.stage == .cleaning)
                                            .contextMenu {
                                                Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                                            }
                                    }
                                }.card()
                            }
                        }
                    }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(detail.id)
                .transition(reduceMotion ? .identity : .offset(x: 14, y: 0).combined(with: .opacity))
                .onAppear { readingDetail = true }
            }
        }
        .clipped()
        .animation(reduceMotion ? nil : Motion.easeOut(0.16), value: detailID)
        .onChange(of: detailID) { id in
            if id == nil { focusedRow = lastOpened; accessibleRow = lastOpened }
        }
    }

    private func summary(_ result: SmartScanAppResult) -> String {
        guard result.count > 0 else { return "Aucun élément attribué dans les catégories analysées." }
        return "\(result.count) \(pl(result.count, "élément")) · \(humanSize(result.bytes)) à examiner"
    }

    private func row(_ result: SmartScanAppResult) -> some View {
        Button {
            lastOpened = result.id
            detailID = result.id
        } label: {
            HStack(spacing: Space.m) {
                SmartScanProfileIcon(profile: result.profile)
                VStack(alignment: .leading, spacing: 3) {
                    Text(result.profile.name).font(AppFont.body.weight(.semibold))
                    Text(summary(result)).font(AppFont.secondary).foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.muted).accessibilityHidden(true)
            }.padding(12).contentShape(Rectangle()).card()
        }
        .buttonStyle(.plainAction)
        .accessibilityLabel(result.profile.name)
        .accessibilityValue(summary(result))
        .accessibilityHint("Ouvre la fiche de nettoyage")
        .focused($focusedRow, equals: result.id)
        .accessibilityFocused($accessibleRow, equals: result.id)
        .disabled(model.stage == .cleaning)
    }
}

private struct SmartScanProfileIcon: View {
    let profile: SmartScanAppProfile
    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                Image(systemName: profile.id == SmartScanAppProfile.other.id ? "folder" : "app.dashed")
                    .font(.title2).foregroundStyle(Theme.muted)
            }
        }.frame(width: 34, height: 34).accessibilityHidden(true)
            .task(id: profile.id) {
                guard profile.id != SmartScanAppProfile.other.id else { return }
                icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: profile.id)
                    .map { NSWorkspace.shared.icon(forFile: $0.path) }
            }
    }
}
