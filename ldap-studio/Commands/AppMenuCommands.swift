//
//  AppMenuCommands.swift
//  ldap-studio
//

import SwiftUI

struct AppMenuCommands: Commands {
    @FocusedValue(\.connectionCommands) private var connectionCommands
    @FocusedValue(\.selectedConnectionCommands) private var selectedConnectionCommands
    @FocusedValue(\.directoryCommands) private var directoryCommands
    @FocusedValue(\.ldifEditorCommands) private var ldifEditorCommands
    @FocusedValue(\.entryDetailCommands) private var entryDetailCommands
    @Environment(\.openWindow) private var openWindow

    /// True when a directory browser window is frontmost — `directoryCommands`
    /// is only published while one is. Used to point ⌘N at whichever "new"
    /// makes sense for the current window.
    private var isBrowsing: Bool { directoryCommands != nil }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Ldap Studio") {
                openWindow(id: "about")
            }
            Divider()
            Button("Check for Updates…") {
                Task { await UpdateChecker.shared.check(userInitiated: true) }
            }
        }

        CommandGroup(replacing: .newItem) {
            Button("New Connection…") {
                connectionCommands?.addConnection()
            }
            .keyboardShortcut("n", modifiers: isBrowsing ? [.command, .shift] : .command)
            .disabled(connectionCommands == nil)

            Button("New Entry…") {
                directoryCommands?.newEntry()
            }
            .keyboardShortcut("n", modifiers: isBrowsing ? .command : [.command, .shift])
            .disabled(directoryCommands == nil || directoryCommands?.isReadOnly == true)
        }

        CommandGroup(after: .newItem) {
            Divider()

            Button("Import Connection…") {
                connectionCommands?.importConnection()
            }
            .disabled(connectionCommands == nil)

            Button("Import LDIF…") {
                directoryCommands?.importLDIF()
            }
            .disabled(directoryCommands == nil || directoryCommands?.isReadOnly == true)

            Button("Open LDIF…") {
                ldifEditorCommands?.openFile()
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(ldifEditorCommands == nil)

            Button("Save LDIF…") {
                ldifEditorCommands?.saveFile()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(ldifEditorCommands == nil)

            Divider()

            Button("Export Connection…") {
                selectedConnectionCommands?.export?()
            }
            .disabled(selectedConnectionCommands?.export == nil)

            Button("Export Entry as LDIF") {
                entryDetailCommands?.exportLDIF()
            }
            .keyboardShortcut("x", modifiers: [.command, .shift])
            .disabled(entryDetailCommands == nil)
        }

        CommandMenu("Connection") {
            Button("Open") {
                selectedConnectionCommands?.open?()
            }
            .disabled(selectedConnectionCommands?.open == nil)

            Button("Edit…") {
                selectedConnectionCommands?.edit?()
            }
            .disabled(selectedConnectionCommands?.edit == nil)

            Button(selectedConnectionCommands?.isFavorite == true ? "Remove from Favorites" : "Add to Favorites") {
                selectedConnectionCommands?.toggleFavorite?()
            }
            .disabled(selectedConnectionCommands?.toggleFavorite == nil)

            Divider()

            Button("Server Info…") {
                directoryCommands?.openServerInfo()
            }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(directoryCommands == nil)

            Divider()

            Button("Delete", role: .destructive) {
                selectedConnectionCommands?.delete?()
            }
            .disabled(selectedConnectionCommands?.delete == nil)
        }

        CommandMenu("Entry") {
            Button("Edit Entry…") {
                directoryCommands?.editEntry?()
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(directoryCommands?.editEntry == nil)

            Button("Schema…") {
                directoryCommands?.openSchema()
            }
            .disabled(directoryCommands == nil)

            Button("LDIF Editor…") {
                directoryCommands?.openLDIFEditor()
            }
            .disabled(directoryCommands == nil)

            Button("Run LDIF") {
                ldifEditorCommands?.run()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(ldifEditorCommands == nil || ldifEditorCommands?.isReadOnly == true)

            Button("Advanced Search…") {
                directoryCommands?.advancedSearch()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(directoryCommands == nil)

            Button("Go to DN…") {
                directoryCommands?.goToDN()
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(directoryCommands == nil)

            Button(directoryCommands?.isSelectedBookmarked == true ? "Remove Bookmark" : "Bookmark Entry") {
                directoryCommands?.toggleBookmark?()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(directoryCommands?.toggleBookmark == nil)

            Divider()

            Button("Rename…") {
                directoryCommands?.renameSelected?()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(directoryCommands?.renameSelected == nil)

            Button("Set Password…") {
                directoryCommands?.setPassword?()
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .disabled(directoryCommands?.setPassword == nil)

            Button("Set Photo…") {
                directoryCommands?.setPhoto?()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .disabled(directoryCommands?.setPhoto == nil)

            Button("Edit Members…") {
                directoryCommands?.editMembers?()
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .disabled(directoryCommands?.editMembers == nil)

            Button("Test Bind…") {
                directoryCommands?.testBind?()
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .disabled(directoryCommands?.testBind == nil)

            Divider()

            Button("Move to…") {
                entryDetailCommands?.moveDN()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(entryDetailCommands == nil || entryDetailCommands?.isReadOnly == true)

            Button("Copy to…") {
                entryDetailCommands?.copyDN()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(entryDetailCommands == nil || entryDetailCommands?.isReadOnly == true)

            Button("Copy DN") {
                directoryCommands?.copyDN?()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(directoryCommands?.copyDN == nil)

            Button("Delete Entry", role: .destructive) {
                directoryCommands?.deleteSelected?()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(directoryCommands?.deleteSelected == nil)

            Divider()

            Button("Refresh") {
                if let refreshSelected = directoryCommands?.refreshSelected {
                    refreshSelected()
                } else {
                    entryDetailCommands?.refresh()
                }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(directoryCommands?.refreshSelected == nil && entryDetailCommands == nil)
        }

        CommandMenu("Attribute") {
            Button("Add Attribute…") {
                entryDetailCommands?.addAttribute()
            }
            .disabled(entryDetailCommands == nil || entryDetailCommands?.isReadOnly == true)

            Button(entryDetailCommands?.showsOperational == true
                ? "Hide Operational Attributes" : "Show Operational Attributes") {
                entryDetailCommands?.toggleOperational()
            }
            .keyboardShortcut("o", modifiers: [.command, .option])
            .disabled(entryDetailCommands == nil)

            Divider()

            Button("View Value") {
                entryDetailCommands?.viewValue?()
            }
            .keyboardShortcut("j", modifiers: .command)
            .disabled(entryDetailCommands?.viewValue == nil)

            Button("Jump to Schema") {
                entryDetailCommands?.jumpToSchema?()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(entryDetailCommands?.jumpToSchema == nil)

            Button("Jump to Object Class") {
                entryDetailCommands?.jumpToObjectClass?()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(entryDetailCommands?.jumpToObjectClass == nil)

            Button("Edit Value…") {
                entryDetailCommands?.editAttribute?()
            }
            .keyboardShortcut("e", modifiers: [.command, .option])
            .disabled(entryDetailCommands?.editAttribute == nil)

            Button("Delete Value", role: .destructive) {
                entryDetailCommands?.deleteAttribute?()
            }
            .keyboardShortcut(.delete, modifiers: [.command, .option])
            .disabled(entryDetailCommands?.deleteAttribute == nil)

            Divider()

            Button("Copy") {
                entryDetailCommands?.copyFull?()
            }
            .keyboardShortcut("c", modifiers: .command)
            .disabled(entryDetailCommands?.copyFull == nil)

            Button("Copy Attribute") {
                entryDetailCommands?.copyAttributeName?()
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
            .disabled(entryDetailCommands?.copyAttributeName == nil)

            Button("Copy Value") {
                entryDetailCommands?.copyValue?()
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
            .disabled(entryDetailCommands?.copyValue == nil)

            Divider()

            Button("Set Password…") {
                entryDetailCommands?.setPassword?()
            }
            .keyboardShortcut("k", modifiers: [.command, .option])
            .disabled(entryDetailCommands?.setPassword == nil)

            Button("Set Photo…") {
                entryDetailCommands?.setPhoto?()
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            .disabled(entryDetailCommands?.setPhoto == nil)
        }
    }
}
