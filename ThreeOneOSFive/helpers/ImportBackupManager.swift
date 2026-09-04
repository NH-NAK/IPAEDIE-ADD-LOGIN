import Foundation

struct ImportedFileRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let targetPath: String
    let relativePath: String
    let fileName: String
    let wasReplaced: Bool
    let backupFileName: String?
    let originalFileSize: Int64?
    var importedAt: Date
}

struct ImportContainerManifest: Codable {
    let containerPath: String
    let bundleID: String?
    var records: [ImportedFileRecord]
}

struct ImportSummary: Equatable {
    let replacedCount: Int
    let addedCount: Int
    let totalCount: Int

    static let empty = ImportSummary(replacedCount: 0, addedCount: 0, totalCount: 0)

    var hasItems: Bool { totalCount > 0 }
}

struct ImportRestoreSummary {
    let restoredOriginalsCount: Int
    let removedNewFilesCount: Int
    let failedCount: Int
    let isSuccess: Bool
}

struct PreparedImportAction {
    let record: ImportedFileRecord
    let isNewBackupCreated: Bool
    let backupFileURL: URL?
}

final class ImportBackupManager {
    static let shared = ImportBackupManager()

    private let fileManager = FileManager.default
    private let lock = NSLock()

    private init() {}

    // MARK: - Path Helpers

    static func containerKey(containerPath: String, bundleID: String?) -> String {
        if let bundleID = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines), !bundleID.isEmpty {
            return bundleID.replacingOccurrences(of: "/", with: "_")
        }
        let stdPath = (containerPath as NSString).standardizingPath
        let hash = UInt32(bitPattern: Int32(truncatingIfNeeded: stdPath.hashValue))
        let folderName = (stdPath as NSString).lastPathComponent
        return "\(folderName)_\(String(format: "%08x", hash))"
    }

    private func backupRootURL() throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = base.appendingPathComponent("ImportTracking", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func containerDirectoryURL(containerPath: String, bundleID: String?) throws -> URL {
        let key = Self.containerKey(containerPath: containerPath, bundleID: bundleID)
        let root = try backupRootURL()
        let dir = root.appendingPathComponent(key, isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func originalsDirectoryURL(containerPath: String, bundleID: String?) throws -> URL {
        let containerDir = try containerDirectoryURL(containerPath: containerPath, bundleID: bundleID)
        let originals = containerDir.appendingPathComponent("originals", isDirectory: true)
        try fileManager.createDirectory(at: originals, withIntermediateDirectories: true)
        return originals
    }

    // MARK: - Manifest Persistence

    private func loadManifest(containerPath: String, bundleID: String?) -> ImportContainerManifest {
        do {
            let containerDir = try containerDirectoryURL(containerPath: containerPath, bundleID: bundleID)
            let manifestURL = containerDir.appendingPathComponent("manifest.json")
            guard fileManager.fileExists(atPath: manifestURL.path) else {
                return ImportContainerManifest(containerPath: containerPath, bundleID: bundleID, records: [])
            }
            let data = try Data(contentsOf: manifestURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(ImportContainerManifest.self, from: data)
        } catch {
            return ImportContainerManifest(containerPath: containerPath, bundleID: bundleID, records: [])
        }
    }

    private func saveManifest(_ manifest: ImportContainerManifest) throws {
        let containerDir = try containerDirectoryURL(containerPath: manifest.containerPath, bundleID: manifest.bundleID)
        let manifestURL = containerDir.appendingPathComponent("manifest.json")
        if manifest.records.isEmpty {
            try? fileManager.removeItem(at: manifestURL)
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
    }

    // MARK: - Import Preparation & Commit

    func prepareRecordBeforeImport(
        targetURL: URL,
        containerPath: String,
        bundleID: String?
    ) -> PreparedImportAction? {
        lock.lock()
        defer { lock.unlock() }

        let canonicalTarget = targetURL.standardizedFileURL.resolvingSymlinksInPath()
        let targetPath = canonicalTarget.path

        let relativePath: String
        if targetPath.hasPrefix(containerPath) {
            let sub = targetPath.dropFirst(containerPath.count)
            relativePath = String(sub).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            relativePath = targetURL.lastPathComponent
        }

        let fileExists = fileManager.fileExists(atPath: targetPath)

        if fileExists {
            let existingManifest = loadManifest(containerPath: containerPath, bundleID: bundleID)
            if let existingRecord = existingManifest.records.first(where: { $0.targetPath == targetPath }),
               let existingBackup = existingRecord.backupFileName {
                do {
                    let originalsDir = try originalsDirectoryURL(containerPath: containerPath, bundleID: bundleID)
                    let backupURL = originalsDir.appendingPathComponent(existingBackup)
                    if fileManager.fileExists(atPath: backupURL.path) {
                        let updatedRecord = ImportedFileRecord(
                            id: existingRecord.id,
                            targetPath: targetPath,
                            relativePath: relativePath,
                            fileName: targetURL.lastPathComponent,
                            wasReplaced: true,
                            backupFileName: existingBackup,
                            originalFileSize: existingRecord.originalFileSize,
                            importedAt: Date()
                        )
                        return PreparedImportAction(record: updatedRecord, isNewBackupCreated: false, backupFileURL: nil)
                    }
                } catch {}
            }

            do {
                let recordID = UUID()
                let backupFileName = "\(recordID.uuidString).original"
                let originalsDir = try originalsDirectoryURL(containerPath: containerPath, bundleID: bundleID)
                let backupURL = originalsDir.appendingPathComponent(backupFileName)

                let attrs = try? fileManager.attributesOfItem(atPath: targetPath)
                let size = (attrs?[.size] as? NSNumber)?.int64Value

                try fileManager.copyItem(at: canonicalTarget, to: backupURL)

                let record = ImportedFileRecord(
                    id: recordID,
                    targetPath: targetPath,
                    relativePath: relativePath,
                    fileName: targetURL.lastPathComponent,
                    wasReplaced: true,
                    backupFileName: backupFileName,
                    originalFileSize: size,
                    importedAt: Date()
                )
                return PreparedImportAction(record: record, isNewBackupCreated: true, backupFileURL: backupURL)
            } catch {
                log("ImportBackupManager: failed to create original backup: \(error.localizedDescription)")
                return nil
            }
        } else {
            let record = ImportedFileRecord(
                id: UUID(),
                targetPath: targetPath,
                relativePath: relativePath,
                fileName: targetURL.lastPathComponent,
                wasReplaced: false,
                backupFileName: nil,
                originalFileSize: nil,
                importedAt: Date()
            )
            return PreparedImportAction(record: record, isNewBackupCreated: false, backupFileURL: nil)
        }
    }

    func commitImportAction(
        _ action: PreparedImportAction,
        containerPath: String,
        bundleID: String?
    ) {
        lock.lock()
        defer { lock.unlock() }

        var manifest = loadManifest(containerPath: containerPath, bundleID: bundleID)
        manifest.records.removeAll(where: { $0.targetPath == action.record.targetPath })
        manifest.records.append(action.record)
        do {
            try saveManifest(manifest)
            log("ImportBackupManager: saved import history for \(action.record.fileName)")
        } catch {
            log("ImportBackupManager: failed to save manifest: \(error.localizedDescription)")
        }
    }

    func cancelImportAction(_ action: PreparedImportAction) {
        lock.lock()
        defer { lock.unlock() }

        if action.isNewBackupCreated, let backupURL = action.backupFileURL {
            try? fileManager.removeItem(at: backupURL)
        }
    }

    // MARK: - Query Status

    func summary(containerPath: String, bundleID: String?) -> ImportSummary {
        lock.lock()
        defer { lock.unlock() }

        let manifest = loadManifest(containerPath: containerPath, bundleID: bundleID)
        let replaced = manifest.records.filter(\.wasReplaced).count
        let added = manifest.records.filter { !$0.wasReplaced }.count
        return ImportSummary(replacedCount: replaced, addedCount: added, totalCount: manifest.records.count)
    }

    func records(containerPath: String, bundleID: String?) -> [ImportedFileRecord] {
        lock.lock()
        defer { lock.unlock() }

        return loadManifest(containerPath: containerPath, bundleID: bundleID).records
            .sorted(by: { $0.importedAt > $1.importedAt })
    }

    func record(forPath path: String, containerPath: String, bundleID: String?) -> ImportedFileRecord? {
        lock.lock()
        defer { lock.unlock() }

        let manifest = loadManifest(containerPath: containerPath, bundleID: bundleID)
        return manifest.records.first(where: { $0.targetPath == path })
    }

    // MARK: - Restore Operations

    func restoreAndCleanAll(
        containerPath: String,
        bundleID: String?
    ) throws -> ImportRestoreSummary {
        lock.lock()
        defer { lock.unlock() }

        var manifest = loadManifest(containerPath: containerPath, bundleID: bundleID)
        guard !manifest.records.isEmpty else {
            return ImportRestoreSummary(restoredOriginalsCount: 0, removedNewFilesCount: 0, failedCount: 0, isSuccess: true)
        }

        let originalsDir = try originalsDirectoryURL(containerPath: containerPath, bundleID: bundleID)
        var restored = 0
        var removed = 0
        var failed = 0
        var remainingRecords: [ImportedFileRecord] = []

        for record in manifest.records {
            let targetURL = URL(fileURLWithPath: record.targetPath)
            if record.wasReplaced {
                guard let backupFileName = record.backupFileName else {
                    failed += 1
                    remainingRecords.append(record)
                    continue
                }
                let backupURL = originalsDir.appendingPathComponent(backupFileName)
                guard fileManager.fileExists(atPath: backupURL.path) else {
                    failed += 1
                    remainingRecords.append(record)
                    continue
                }
                do {
                    let parentDir = targetURL.deletingLastPathComponent()
                    try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
                    try atomicRestore(from: backupURL, to: targetURL)
                    restored += 1
                    try? fileManager.removeItem(at: backupURL)
                } catch {
                    log("ImportBackupManager: failed to restore \(record.targetPath): \(error.localizedDescription)")
                    failed += 1
                    remainingRecords.append(record)
                }
            } else {
                if fileManager.fileExists(atPath: record.targetPath) {
                    do {
                        try fileManager.removeItem(atPath: record.targetPath)
                        removed += 1
                    } catch {
                        log("ImportBackupManager: failed to delete imported file \(record.targetPath): \(error.localizedDescription)")
                        failed += 1
                        remainingRecords.append(record)
                    }
                } else {
                    removed += 1
                }
            }
        }

        manifest.records = remainingRecords
        try saveManifest(manifest)

        if remainingRecords.isEmpty {
            let containerDir = try containerDirectoryURL(containerPath: containerPath, bundleID: bundleID)
            try? fileManager.removeItem(at: containerDir)
        }

        return ImportRestoreSummary(
            restoredOriginalsCount: restored,
            removedNewFilesCount: removed,
            failedCount: failed,
            isSuccess: failed == 0
        )
    }

    func restoreSingleRecord(
        _ record: ImportedFileRecord,
        containerPath: String,
        bundleID: String?
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        var manifest = loadManifest(containerPath: containerPath, bundleID: bundleID)
        guard let index = manifest.records.firstIndex(where: { $0.id == record.id }) else { return }

        let targetURL = URL(fileURLWithPath: record.targetPath)
        if record.wasReplaced {
            let originalsDir = try originalsDirectoryURL(containerPath: containerPath, bundleID: bundleID)
            guard let backupFileName = record.backupFileName else {
                throw NSError(domain: "ImportBackupManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Backup file missing"])
            }
            let backupURL = originalsDir.appendingPathComponent(backupFileName)
            guard fileManager.fileExists(atPath: backupURL.path) else {
                throw NSError(domain: "ImportBackupManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Original backup file missing"])
            }
            let parentDir = targetURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
            try atomicRestore(from: backupURL, to: targetURL)
            try? fileManager.removeItem(at: backupURL)
        } else {
            if fileManager.fileExists(atPath: record.targetPath) {
                try fileManager.removeItem(atPath: record.targetPath)
            }
        }

        manifest.records.remove(at: index)
        try saveManifest(manifest)
        if manifest.records.isEmpty {
            let containerDir = try containerDirectoryURL(containerPath: containerPath, bundleID: bundleID)
            try? fileManager.removeItem(at: containerDir)
        }
    }

    func commitAsNewOriginals(
        containerPath: String,
        bundleID: String?
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        let containerDir = try containerDirectoryURL(containerPath: containerPath, bundleID: bundleID)
        try? fileManager.removeItem(at: containerDir)
    }

    // MARK: - Private Helpers

    private func atomicRestore(from source: URL, to target: URL) throws {
        let staging = target.deletingLastPathComponent()
            .appendingPathComponent(".3105-restore-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: staging) }
        try fileManager.copyItem(at: source, to: staging)
        if let attrs = try? fileManager.attributesOfItem(atPath: target.path) {
            var retained: [FileAttributeKey: Any] = [:]
            if let posix = attrs[.posixPermissions] { retained[.posixPermissions] = posix }
            if let prot = attrs[.protectionKey] { retained[.protectionKey] = prot }
            if !retained.isEmpty {
                try? fileManager.setAttributes(retained, ofItemAtPath: staging.path)
            }
        }
        guard rename(staging.path, target.path) == 0 else {
            try? fileManager.removeItem(at: target)
            try fileManager.moveItem(at: staging, to: target)
            return
        }
    }
}
