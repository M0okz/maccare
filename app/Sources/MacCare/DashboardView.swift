import SwiftUI

/// Tableau de bord alimenté par les mesures du Mac.
struct DashboardView: View {
    let layout: MainWindowLayout
    @ObservedObject var app: AppState
    @ObservedObject private var permissions: PermissionsModel
    @State private var disk = DiskSpace.current()
    @State private var showingPermissions = false

    init(app: AppState, layout: MainWindowLayout) {
        self.layout = layout
        self.app = app
        self.permissions = app.permissions
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = layout.dashboardScale(forContentWidth: geometry.size.width)
            let availableWidth = geometry.size.width / scale
            let inset: CGFloat = availableWidth < 1050 ? 20 : 26
            let width = min(availableWidth - 2 * inset, 1440)
            VStack(alignment: .leading, spacing: 14 * scale) {
                HStack {
                    Text("État du Mac").font(AppFont.pageTitle).accessibilityAddTraits(.isHeader)
                    Spacer()
                    QuickToolsButton(app: app)
                }
                .dashboardBlockScale(scale)
                HomeStatusCards(scale: scale, app: app, availableWidth: width,
                                storage: disk.flatMap { TrayStorageUsage(free: $0.free, total: $0.total) })
            }
            .frame(width: width * scale)
            .padding(.top, 20 * scale).padding(.bottom, 10 * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .overlay(alignment: .bottomTrailing) {
                if showsPermissionReminder {
                    permissionReminder
                        .dashboardBlockScale(scale)
                        .padding(.trailing, (max(inset, (availableWidth - width) / 2) + 46) * scale)
                        .padding(.bottom, 14 * scale)
                }
            }
        }
        .onAppear {
            disk = DiskSpace.current()
        }
    }

    private var showsPermissionReminder: Bool {
        permissions.hasChecked && permissions.showBanner
    }

    private var permissionTitle: String {
        if permissions.fullDisk == .unknown || permissions.automation == .unknown {
            return "Vérifier les autorisations"
        }
        return permissions.missing.count == 1 ? "1 autorisation manquante" : "\(permissions.missing.count) autorisations manquantes"
    }

    private var permissionReminder: some View {
        Button { showingPermissions.toggle() } label: {
            Label(permissionTitle, systemImage: "lock.fill")
                .font(AppFont.caption.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Theme.window, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.warn.opacity(0.48)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plainAction).foregroundStyle(Theme.warn)
        .shadow(color: .black.opacity(0.24), radius: 5, y: 2)
        .accessibilityHint("Afficher les accès à configurer")
        .popover(isPresented: $showingPermissions, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Autorisations").font(.headline).accessibilityAddTraits(.isHeader)
                    Spacer()
                    PopoverCloseButton { showingPermissions = false }
                }
                ForEach(permissions.missing, id: \.self) { access in
                    Label(access, systemImage: "lock").font(AppFont.body)
                }
                Text("Certaines analyses sont incomplètes.").font(AppFont.secondary)
                    .foregroundStyle(.secondary)
                Button("Configurer") {
                    showingPermissions = false
                    permissions.reopen()
                }
                .buttonStyle(.actionPill)
            }
            .padding(16)
            .onExitCommand { showingPermissions = false }
        }
    }
}
