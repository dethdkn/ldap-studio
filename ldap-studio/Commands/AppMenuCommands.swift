//
//  AppMenuCommands.swift
//  ldap-studio
//

import SwiftUI

struct AppMenuCommands: Commands {
    @FocusedValue(\.connectionCommands) private var connectionCommands
    @FocusedValue(\.selectedConnectionCommands) private var selectedConnectionCommands
    @FocusedValue(\.directoryCommands) private var directoryCommands
    @FocusedValue(\.entryDetailCommands) private var entryDetailCommands

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Connection…") {
                connectionCommands?.addConnection()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(connectionCommands == nil)

            Button("New Entry…") {
                directoryCommands?.newEntry()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(directoryCommands == nil)
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
            .disabled(directoryCommands == nil)

            Divider()

            Button("Export Connection…") {
                selectedConnectionCommands?.export?()
            }
            .disabled(selectedConnectionCommands?.export == nil)

            Button("Export Entry as LDIF") {
                entryDetailCommands?.exportLDIF()
            }
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

            Divider()

            Button("Delete", role: .destructive) {
                selectedConnectionCommands?.delete?()
            }
            .disabled(selectedConnectionCommands?.delete == nil)
        }

        CommandMenu("Entry") {
            Button("Schema…") {
                directoryCommands?.openSchema()
            }
            .disabled(directoryCommands == nil)

            Button("Advanced Search…") {
                directoryCommands?.advancedSearch()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(directoryCommands == nil)

            Divider()

            Button("Move DN…") {
                entryDetailCommands?.moveDN()
            }
            .disabled(entryDetailCommands == nil)

            Button("Copy DN…") {
                entryDetailCommands?.copyDN()
            }
            .disabled(entryDetailCommands == nil)

            Button("Delete Entry", role: .destructive) {
                directoryCommands?.deleteSelected?()
            }
            .disabled(directoryCommands?.deleteSelected == nil)

            Divider()

            Button("Refresh") {
                entryDetailCommands?.refresh()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(entryDetailCommands == nil)
        }

        CommandMenu("Attribute") {
            Button("Add Attribute…") {
                entryDetailCommands?.addAttribute()
            }
            .disabled(entryDetailCommands == nil)

            Button("View Value") {
                entryDetailCommands?.viewValue?()
            }
            .disabled(entryDetailCommands?.viewValue == nil)

            Button("Edit Value…") {
                entryDetailCommands?.editAttribute?()
            }
            .disabled(entryDetailCommands?.editAttribute == nil)

            Button("Delete Value", role: .destructive) {
                entryDetailCommands?.deleteAttribute?()
            }
            .disabled(entryDetailCommands?.deleteAttribute == nil)

            Divider()

            Button("Copy") {
                entryDetailCommands?.copyFull?()
            }
            .disabled(entryDetailCommands?.copyFull == nil)

            Button("Copy Attribute") {
                entryDetailCommands?.copyAttributeName?()
            }
            .disabled(entryDetailCommands?.copyAttributeName == nil)

            Button("Copy Value") {
                entryDetailCommands?.copyValue?()
            }
            .disabled(entryDetailCommands?.copyValue == nil)

            Divider()

            Button("Set Password…") {
                entryDetailCommands?.setPassword?()
            }
            .disabled(entryDetailCommands?.setPassword == nil)

            Button("Set Photo…") {
                entryDetailCommands?.setPhoto?()
            }
            .disabled(entryDetailCommands?.setPhoto == nil)
        }
    }
}
