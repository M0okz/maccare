import Foundation

enum AIClutterGroup: String, CaseIterable, Identifiable {
    case caches, history, models
    var id: String { rawValue }
    var title: String {
        switch self {
        case .caches: return "Caches et fichiers temporaires"
        case .history: return "Historiques et journaux"
        case .models: return "Modèles locaux"
        }
    }
    var detail: String {
        switch self {
        case .caches: return "Ces fichiers pourront être recréés par vos outils d’IA."
        case .history: return "Les conversations locales et journaux retirés ne seront plus disponibles dans l’application."
        case .models: return "Les modèles retirés devront être téléchargés à nouveau. La bibliothèque Ollama est proposée en entier pour conserver la cohérence entre ses modèles partagés."
        }
    }
}

struct AIClutterLocation: Identifiable {
    let path: String
    let application: String
    let label: String
    let group: AIClutterGroup
    var id: String { path }
}

/// Liste fermée : jamais les racines .codex/.claude, identifiants, réglages, mémoires ou projets.
enum AIClutterCatalog {
    static func locations(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [AIClutterLocation] {
        var result: [AIClutterLocation] = []
        func add(_ app: String, _ relative: String, _ label: String, _ group: AIClutterGroup) {
            result.append(.init(path: home.appendingPathComponent(relative).path,
                                application: app, label: label, group: group))
        }
        for (app, bundle, support) in [
            ("Codex", "com.openai.codex", "Codex"),
            ("Claude", "com.anthropic.claudefordesktop", "Claude"),
            ("ChatGPT", "com.openai.chat", "com.openai.chat"),
            ("Cursor", "com.todesktop.230313mzl4w4u92", "Cursor")
        ] {
            add(app, "Library/Caches/\(bundle)", "Caches de l’application", .caches)
            for name in ["Cache", "Code Cache", "GPUCache", "DawnCache", "CachedData"] {
                add(app, "Library/Application Support/\(support)/\(name)", name, .caches)
            }
            add(app, "Library/Logs/\(support)", "Journaux", .history)
            add(app, "Library/Application Support/\(support)/logs", "Journaux de l’application", .history)
        }
        add("Codex", ".codex/tmp", "Fichiers temporaires", .caches)
        add("Codex", ".codex/log", "Journaux CLI", .history)
        add("Codex", ".codex/sessions", "Conversations locales", .history)
        add("Codex", ".codex/archived_sessions", "Conversations archivées", .history)
        add("Claude Code", ".claude/debug", "Journaux de diagnostic", .history)
        add("Claude Code", ".claude/projects", "Historique local des conversations par projet", .history)
        add("Claude Code", ".claude/file-history", "Historique local des versions de fichiers", .history)
        add("Gemini CLI", ".gemini/tmp", "Sessions et fichiers temporaires", .history)
        add("Ollama", ".ollama/models", "Bibliothèque complète de modèles", .models)
        // Deux versions de l'emplacement LM Studio, puis caches de modèles Hugging Face.
        for relative in [".lmstudio/models", ".cache/lm-studio/models"] {
            let root = home.appendingPathComponent(relative)
            for author in directories(root) {
                for model in directories(author) {
                    result.append(.init(path: model.path, application: "LM Studio", label: "\(author.lastPathComponent)/\(model.lastPathComponent)", group: .models))
                }
            }
        }
        for model in directories(home.appendingPathComponent(".cache/huggingface/hub")) where model.lastPathComponent.hasPrefix("models--") {
            result.append(.init(path: model.path, application: "Hugging Face", label: model.lastPathComponent.replacingOccurrences(of: "models--", with: ""), group: .models))
        }
        return result
    }

    private static func directories(_ root: URL) -> [URL] {
        let values = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])) ?? []
        return values.filter {
            guard let v = try? $0.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
            return v.isDirectory == true && v.isSymbolicLink != true
        }
    }
}
