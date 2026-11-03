import AppKit

/// Accepte clavier et VoiceOver sans être comptée comme fenêtre principale de MacCare.
final class TrayFloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
