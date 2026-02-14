import AppKit

// Helper for NSMenu actions (used by ContentView's file menu button)
@MainActor
class FileMenuActions: NSObject {
    static let shared = FileMenuActions()
    var model: SequencerModel?
    
    @objc func newDoc(_ sender: Any?) { model?.newDocument() }
    @objc func openDoc(_ sender: Any?) { model?.showOpenDialog() }
    @objc func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        try? model?.load(from: url)
    }
    @objc func clearRecents(_ sender: Any?) { SequencerModel.clearRecentFiles() }
    @objc func revealInFinder(_ sender: Any?) {
        guard let url = model?.currentFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
