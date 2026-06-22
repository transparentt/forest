import Foundation

extension FileManager {
    func setExecutable(at url: URL) throws {
        var values = try attributesOfItem(atPath: url.path)
        values[.posixPermissions] = 0o755
        try setAttributes(values, ofItemAtPath: url.path)
    }
}
