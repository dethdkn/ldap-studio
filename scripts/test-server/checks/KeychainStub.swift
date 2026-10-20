// Stands in for the app's KeychainService: the checks keep passwords in memory.
import Foundation
enum KeychainService {
    static var passwords: [UUID: String] = [:]
    static func readPassword(for id: UUID) -> String? { passwords[id] }
    static func readSSHPassword(for id: UUID) -> String? { nil }
}
