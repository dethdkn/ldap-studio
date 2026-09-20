//
//  AppFocusedValues.swift
//  ldap-studio
//

import SwiftUI

/// Everything the top menu bar can trigger, grouped by which window/view
/// actually owns the behavior — each group is published via
/// `.focusedSceneValue` from the view that owns it, so the menu bar always
/// acts on whichever window is actually frontmost, and disables itself
/// automatically when that window (or a required selection within it)
/// isn't there.

struct ConnectionCommands {
    var addConnection: () -> Void
    var importConnection: () -> Void
}

struct SelectedConnectionCommands {
    var open: (() -> Void)?
    var edit: (() -> Void)?
    var export: (() -> Void)?
    var delete: (() -> Void)?
    /// Toggles the selected connection's favorite flag; nil with no
    /// single selection. `isFavorite` drives the menu-item label.
    var toggleFavorite: (() -> Void)?
    var isFavorite: Bool = false
}

struct DirectoryCommands {
    var newEntry: () -> Void
    var importLDIF: () -> Void
    var openSchema: () -> Void
    var openLDIFEditor: () -> Void
    var openServerInfo: () -> Void
    var advancedSearch: () -> Void
    /// Opens the "Go to DN" quick-jump.
    var goToDN: () -> Void
    /// Pins/unpins the selected entry's DN; nil when nothing is selected.
    var toggleBookmark: (() -> Void)?
    /// Whether the selected entry is already bookmarked (for the menu label).
    var isSelectedBookmarked: Bool
    /// The connection is read-only — write menu items disable themselves.
    var isReadOnly: Bool
    /// Opens the dedicated Edit Entry window; nil when nothing is selected.
    var editEntry: (() -> Void)?
    /// The following act on the tree's selected entry — nil when nothing is
    /// selected, and `setPassword` / `setPhoto` are also nil when the
    /// entry's object classes don't allow that attribute.
    var refreshSelected: (() -> Void)?
    var renameSelected: (() -> Void)?
    var copyDN: (() -> Void)?
    /// Exports every selected tree entry into one LDIF file.
    var exportSelected: (() -> Void)?
    var setPassword: (() -> Void)?
    var setPhoto: (() -> Void)?
    /// Opens the "Test Bind" diagnostic for the selected entry; read-only,
    /// so it's available regardless of `isReadOnly`.
    var testBind: (() -> Void)?
    var deleteSelected: (() -> Void)?
    /// Non-nil only when the selected entry is a group.
    var editMembers: (() -> Void)?
}

struct LDIFEditorCommands {
    var openFile: () -> Void
    var saveFile: () -> Void
    var run: () -> Void
    var isReadOnly: Bool = false
}

struct EntryDetailCommands {
    var addAttribute: () -> Void
    var editAttribute: (() -> Void)?
    var deleteAttribute: (() -> Void)?
    var moveDN: () -> Void
    var copyDN: () -> Void
    var exportLDIF: () -> Void
    var refresh: () -> Void
    var viewValue: (() -> Void)?
    /// Opens the Schema window scrolled to the selected attribute's type.
    var jumpToSchema: (() -> Void)?
    /// Opens the Schema window scrolled to the class named in the selected
    /// `objectClass` value row; nil when the selection isn't one.
    var jumpToObjectClass: (() -> Void)?
    var copyFull: (() -> Void)?
    var copyAttributeName: (() -> Void)?
    var copyValue: (() -> Void)?
    var setPassword: (() -> Void)?
    var setPhoto: (() -> Void)?
    /// Shows/hides the server-maintained operational attributes.
    var toggleOperational: () -> Void
    var showsOperational: Bool
    /// The connection is read-only — write menu items disable themselves.
    var isReadOnly: Bool = false
}

private struct ConnectionCommandsKey: FocusedValueKey {
    typealias Value = ConnectionCommands
}

private struct SelectedConnectionCommandsKey: FocusedValueKey {
    typealias Value = SelectedConnectionCommands
}

private struct DirectoryCommandsKey: FocusedValueKey {
    typealias Value = DirectoryCommands
}

private struct LDIFEditorCommandsKey: FocusedValueKey {
    typealias Value = LDIFEditorCommands
}

private struct EntryDetailCommandsKey: FocusedValueKey {
    typealias Value = EntryDetailCommands
}

extension FocusedValues {
    var connectionCommands: ConnectionCommands? {
        get { self[ConnectionCommandsKey.self] }
        set { self[ConnectionCommandsKey.self] = newValue }
    }

    var selectedConnectionCommands: SelectedConnectionCommands? {
        get { self[SelectedConnectionCommandsKey.self] }
        set { self[SelectedConnectionCommandsKey.self] = newValue }
    }

    var directoryCommands: DirectoryCommands? {
        get { self[DirectoryCommandsKey.self] }
        set { self[DirectoryCommandsKey.self] = newValue }
    }

    var ldifEditorCommands: LDIFEditorCommands? {
        get { self[LDIFEditorCommandsKey.self] }
        set { self[LDIFEditorCommandsKey.self] = newValue }
    }

    var entryDetailCommands: EntryDetailCommands? {
        get { self[EntryDetailCommandsKey.self] }
        set { self[EntryDetailCommandsKey.self] = newValue }
    }
}
