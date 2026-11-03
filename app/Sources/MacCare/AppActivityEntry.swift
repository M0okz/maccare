import Foundation

/// Historique borné de la session, alimenté par les vrais comptes rendus des modèles.
struct AppActivityEntry: Identifiable {
    let id = UUID()
    let date: Date
    let title: String
    let detail: String
    let module: Module
}
