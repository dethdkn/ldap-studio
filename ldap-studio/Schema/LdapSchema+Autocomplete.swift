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

    /// Every object class's primary name — for the `objectClass` value
    /// field's own autocomplete.
    var allObjectClassNames: [String] {
        objectClasses
            .compactMap { $0.names.first }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
