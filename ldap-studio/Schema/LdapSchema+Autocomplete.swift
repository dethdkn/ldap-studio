//
//  LdapSchema+Autocomplete.swift
//  ldap-studio
//

import Foundation

extension LdapSchema {
    /// Every attribute name allowed on an entry with the given object
    /// classes — each class's own MUST and MAY, plus everything inherited
    /// from its superior classes all the way up to `top`. Purely additive
    /// suggestions: this never restricts what the user can actually type.
    func allowedAttributeNames(forObjectClasses objectClassNames: [String]) -> [String] {
        var visited = Set<String>()
        var result = Set<String>()

        func visit(_ name: String) {
            let key = name.lowercased()
            guard !visited.contains(key) else { return }
            visited.insert(key)
            guard let objectClass = objectClasses.first(where: { oc in
                oc.names.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
            }) else { return }
            result.formUnion(objectClass.must)
            result.formUnion(objectClass.may)
            for superior in objectClass.superiorClasses {
                visit(superior)
            }
        }

        for name in objectClassNames {
            visit(name)
        }

        return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Whether the schema actually knows at least one of these object-class
    /// names. Callers use this to tell "the schema says no" apart from "the
    /// schema has never heard of these classes" — the latter shouldn't gate
    /// anything.
    func recognizesAnyObjectClass(_ objectClassNames: [String]) -> Bool {
        objectClassNames.contains { name in
            objectClasses.contains { oc in
                oc.names.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
            }
        }
    }

    /// Whether an entry with these object classes is allowed to carry
    /// `attributeName` — i.e. it's in some class's MUST or MAY, inheritance
    /// included.
    func permitsAttribute(_ attributeName: String, forObjectClasses objectClassNames: [String]) -> Bool {
        allowedAttributeNames(forObjectClasses: objectClassNames)
            .contains { $0.caseInsensitiveCompare(attributeName) == .orderedSame }
    }

    /// Every object class's primary name — for the `objectClass` value
    /// field's own autocomplete.
    var allObjectClassNames: [String] {
        objectClasses
            .compactMap { $0.names.first }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Primary names of the classes of a given kind ("STRUCTURAL",
    /// "AUXILIARY", "ABSTRACT"), sorted.
    func objectClassNames(ofKind kind: String) -> [String] {
        objectClasses
            .filter { $0.kind.caseInsensitiveCompare(kind) == .orderedSame }
            .compactMap { $0.names.first }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    struct RequiredOptionalAttributes {
        var must: [String]
        var may: [String]
    }

    /// The MUST (required) and MAY (optional) attribute names for an entry
    /// with the given object classes, gathering each class's own plus
    /// everything inherited from its superiors. Anything that's MUST for
    /// any class is treated as required overall (removed from `may`).
    func requiredAndOptionalAttributes(forObjectClasses objectClassNames: [String]) -> RequiredOptionalAttributes {
        var visited = Set<String>()
        var must = Set<String>()
        var may = Set<String>()

        func visit(_ name: String) {
            let key = name.lowercased()
            guard !visited.contains(key) else { return }
            visited.insert(key)
            guard let objectClass = objectClasses.first(where: { oc in
                oc.names.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
            }) else { return }
            must.formUnion(objectClass.must)
            may.formUnion(objectClass.may)
            for superior in objectClass.superiorClasses {
                visit(superior)
            }
        }

        for name in objectClassNames {
            visit(name)
        }
        may.subtract(must)

        func sorted(_ set: Set<String>) -> [String] {
            set.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
        return RequiredOptionalAttributes(must: sorted(must), may: sorted(may))
    }
}
