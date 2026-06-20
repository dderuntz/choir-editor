import AppKit
import UniformTypeIdentifiers
import os

private let log = Logger(subsystem: "com.choir-arranger", category: "file")

// Centralises file-dialog presentation and NSMenu actions.
// The model owns save(to:)/load(from:); this layer owns the panels.
@MainActor
class FileMenuActions: NSObject {
    static let shared = FileMenuActions()
    var model: SequencerModel?

    /// OP-XY export is hidden by default until the feature is fully resolved.
    /// Development can opt in by setting CHOIR_ENABLE_XY_EXPORT=1.
    static var isXYExportEnabled: Bool {
        ProcessInfo.processInfo.environment["CHOIR_ENABLE_XY_EXPORT"] == "1"
    }
    
    // MARK: - NSMenu targets (toolbar file button)
    
    @objc func newDoc(_ sender: Any?) { model?.newDocument() }
    @objc func openDoc(_ sender: Any?) { showOpenDialog() }
    @objc func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        try? model?.load(from: url)
    }
    @objc func clearRecents(_ sender: Any?) { SequencerModel.clearRecentFiles() }
    @objc func revealInFinder(_ sender: Any?) {
        guard let url = model?.currentFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
    // MARK: - File Dialogs
    
    /// Save to current file, or show Save As if no file yet. Returns true if saved.
    @discardableResult
    func saveCurrentOrPrompt() -> Bool {
        guard let model else { return false }
        if let url = model.currentFileURL {
            do {
                try model.save(to: url)
                return true
            } catch {
                log.error("Error saving: \(error)")
                return false
            }
        } else {
            return showSaveDialog()
        }
    }
    
    /// Show NSSavePanel and save. Returns true if saved.
    @discardableResult
    func showSaveDialog() -> Bool {
        guard let model else { return false }
        let panel = NSSavePanel()
        panel.title = "Save Choir Sequence"
        panel.nameFieldStringValue = model.documentName == "Untitled" ? "Untitled.choir" : "\(model.documentName).choir"
        panel.allowedContentTypes = [.init(filenameExtension: "choir") ?? .json]
        panel.allowsOtherFileTypes = false
        panel.isExtensionHidden = false
        
        guard panel.runModal() == .OK, var url = panel.url else { return false }
        
        // Ensure .choir extension
        if url.pathExtension != "choir" {
            url = url.appendingPathExtension("choir")
        }
        
        do {
            try model.save(to: url)
            return true
        } catch {
            log.error("Error saving: \(error)")
            return false
        }
    }
    
    /// Export as Standard MIDI File.
    @discardableResult
    func showExportMIDIDialog() -> Bool {
        guard let model else { return false }
        let panel = NSSavePanel()
        panel.title = "Export as MIDI"
        let baseName = model.documentName == "Untitled" ? "Untitled" : model.documentName
        panel.nameFieldStringValue = "\(baseName).mid"
        panel.allowedContentTypes = [.midi]
        panel.allowsOtherFileTypes = false
        panel.isExtensionHidden = false
        
        guard panel.runModal() == .OK, var url = panel.url else { return false }
        
        if url.pathExtension != "mid" && url.pathExtension != "midi" {
            url = url.appendingPathExtension("mid")
        }
        
        do {
            try model.exportMIDI(to: url)
            return true
        } catch {
            log.error("Error exporting MIDI: \(error)")
            return false
        }
    }
    
    @objc func exportMIDI(_ sender: Any?) { showExportMIDIDialog() }

    /// Export as OP-XY project file.
    @discardableResult
    func showExportXYDialog() -> Bool {
        guard Self.isXYExportEnabled else { return false }
        guard let model else { return false }
        let panel = NSSavePanel()
        panel.title = "Export as OP-XY"
        let baseName = model.documentName == "Untitled" ? "Untitled" : model.documentName
        panel.nameFieldStringValue = "\(baseName).xy"
        panel.allowedContentTypes = [.init(filenameExtension: "xy") ?? .data]
        panel.allowsOtherFileTypes = false
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, var url = panel.url else { return false }

        if url.pathExtension != "xy" {
            url = url.appendingPathExtension("xy")
        }

        do {
            try model.exportXY(to: url)
            return true
        } catch {
            log.error("Error exporting OP-XY: \(error)")
            showExportError(error)
            return false
        }
    }

    private func showExportError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "OP-XY Export Failed"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc func exportXY(_ sender: Any?) {
        guard Self.isXYExportEnabled else { return }
        showExportXYDialog()
    }
    
    /// Show NSOpenPanel and load. Returns true if loaded.
    @discardableResult
    func showOpenDialog() -> Bool {
        guard let model else { return false }
        let panel = NSOpenPanel()
        panel.title = "Open Choir Sequence"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.init(filenameExtension: "choir") ?? .json]
        
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        
        do {
            try model.load(from: url)
            return true
        } catch {
            log.error("Error loading: \(error)")
            return false
        }
    }
}
