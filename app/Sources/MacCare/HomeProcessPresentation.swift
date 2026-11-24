import SwiftUI

@MainActor
final class HomeProcessDetailSession: ObservableObject {
    struct Selection {
        let id: TrayProcess.Identity
        let inspection: HomeProcessInspection?
    }

    let opened: HomeProcessGroup
    let controller: TrayProcessController
    @Published var group: HomeProcessGroup?
    @Published var selection: Selection?

    init(_ group: HomeProcessGroup, controller: TrayProcessController) {
        opened = group
        self.group = group
        self.controller = controller
    }
}

@MainActor
final class HomeProcessPresentation: ObservableObject {
    @Published private(set) var presented: HomeProcessDetailSession?
    private var preparing: HomeProcessDetailSession?
    private var request: Task<Void, Never>?

    func open(_ group: HomeProcessGroup, member: TrayProcess?, controller: TrayProcessController) {
        let session = HomeProcessDetailSession(group, controller: controller)
        preparing = session
        select(member ?? group.primary ?? group.members[0], in: session)
    }

    func select(_ process: TrayProcess, in session: HomeProcessDetailSession) {
        request?.cancel()
        request = Task {
            let details = await Task.detached(priority: .userInitiated) { HomeProcessInspection.read(process) }.value
            guard !Task.isCancelled else { return }
            session.selection = .init(id: process.id, inspection: details)
            if preparing === session {
                preparing = nil
                presented = session
            }
        }
    }

    func refresh(_ groups: [HomeProcessGroup]) {
        guard let session = preparing ?? presented else { return }
        session.group = groups.first { $0.id == session.opened.id }
    }

    func close() {
        request?.cancel()
        request = nil
        preparing = nil
        presented = nil
    }
}

struct HomeProcessModal: ViewModifier {
    @StateObject private var presentation = HomeProcessPresentation()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .environmentObject(presentation)
            .disabled(presentation.presented != nil)
            .accessibilityHidden(presentation.presented != nil)
            .overlay {
                if let session = presentation.presented {
                    ZStack {
                        Color.black.opacity(0.32)
                            .onTapGesture { presentation.close() }
                            .accessibilityHidden(true)
                        HomeProcessDetails(session: session, controller: session.controller, presentation: presentation)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .contentShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.32), radius: 20, y: 6)
                            .accessibilityElement(children: .contain)
                            .accessibilityAddTraits(.isModal)
                    }
                    .ignoresSafeArea()
                    .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: presentation.presented != nil)
    }
}
