import Foundation

enum DevicePatchService {
    static func apply(project: PatchProject) throws -> PatchTransactionReceipt {
        let bundleIDs = orderedBundleIdentifiers(in: project)
        return try withResolvedContainers(bundleIDs: bundleIDs) { roots in
            try PatchTransaction.apply(
                project: project,
                backupRoot: try PatchProjectLibrary.backupRootURL(),
                containerResolver: { bundleID in
                    guard let root = roots[bundleID] else {
                        throw PatchPackageError.targetAppUnavailable(bundleID)
                    }
                    return root
                }
            )
        }
    }

    static func inspectRestore(receipt: PatchTransactionReceipt) throws -> PatchRestoreInspection {
        let bundleIDs = try PatchTransaction.requiredBundleIdentifiers(for: receipt)
        return try withResolvedContainers(bundleIDs: bundleIDs) { roots in
            try PatchTransaction.inspectRestore(
                receipt: receipt,
                containerResolver: { bundleID in
                    guard let root = roots[bundleID] else {
                        throw PatchPackageError.targetAppUnavailable(bundleID)
                    }
                    return root
                }
            )
        }
    }

    static func restore(
        receipt: PatchTransactionReceipt,
        allowChangedTargets: Bool = false
    ) throws {
        let bundleIDs = try PatchTransaction.requiredBundleIdentifiers(for: receipt)
        try withResolvedContainers(bundleIDs: bundleIDs) { roots in
            try PatchTransaction.restore(
                receipt: receipt,
                allowChangedTargets: allowChangedTargets,
                containerResolver: { bundleID in
                    guard let root = roots[bundleID] else {
                        throw PatchPackageError.targetAppUnavailable(bundleID)
                    }
                    return root
                }
            )
        }
        let key = "mod_applied_\(receipt.projectID.uuidString)"
        UserDefaults.standard.set(false, forKey: key)
        UserDefaults.standard.synchronize()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("AllPatchesDidRestoreNotification"), object: nil)
        }
    }

    static func resetToAppliedState(
        receipt: PatchTransactionReceipt,
        project: PatchProject
    ) throws {
        let bundleIDs = try PatchTransaction.requiredBundleIdentifiers(for: receipt)
        try withResolvedContainers(bundleIDs: bundleIDs) { roots in
            try PatchTransaction.resetToAppliedState(
                receipt: receipt,
                fallbackProject: project,
                containerResolver: { bundleID in
                    guard let root = roots[bundleID] else {
                        throw PatchPackageError.targetAppUnavailable(bundleID)
                    }
                    return root
                }
            )
        }
    }

    static func latestReceipt(projectID: UUID) -> PatchTransactionReceipt? {
        guard let backupRoot = try? PatchProjectLibrary.backupRootURL() else { return nil }
        return PatchTransaction.latestReceipt(projectID: projectID, backupRoot: backupRoot)
    }

    static func isProjectApplied(projectID: UUID) -> Bool {
        let key = "mod_applied_\(projectID.uuidString)"
        let hasReceipt = latestReceipt(projectID: projectID) != nil
        if !hasReceipt {
            return false
        }
        let savedState = UserDefaults.standard.object(forKey: key) as? Bool
        return savedState ?? true
    }

    @discardableResult
    static func setProjectApplied(project: PatchProject, enabled: Bool) throws -> Bool {
        let key = "mod_applied_\(project.id.uuidString)"
        if enabled {
            _ = try apply(project: project)
            UserDefaults.standard.set(true, forKey: key)
            UserDefaults.standard.synchronize()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Notification.Name("AllPatchesDidRestoreNotification"), object: nil)
            }
            return true
        } else {
            if let receipt = latestReceipt(projectID: project.id) {
                try restore(receipt: receipt, allowChangedTargets: true)
            } else {
                UserDefaults.standard.set(false, forKey: key)
                UserDefaults.standard.synchronize()
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Notification.Name("AllPatchesDidRestoreNotification"), object: nil)
                }
            }
            return false
        }
    }

    @discardableResult
    static func restoreAllAppliedPatches() throws -> Int {
        guard let backupRoot = try? PatchProjectLibrary.backupRootURL() else { return 0 }
        let receipts = PatchTransaction.allAppliedReceipts(backupRoot: backupRoot)
        var restoredCount = 0
        for receipt in receipts {
            do {
                try restore(receipt: receipt, allowChangedTargets: true)
                let key = "mod_applied_\(receipt.projectID.uuidString)"
                UserDefaults.standard.set(false, forKey: key)
                restoredCount += 1
            } catch {
                // Continue restoring remaining receipts
            }
        }
        
        // Reset all mod_applied_* keys in UserDefaults so all apply toggles turn OFF
        let dictionary = UserDefaults.standard.dictionaryRepresentation()
        for key in dictionary.keys where key.hasPrefix("mod_applied_") {
            UserDefaults.standard.set(false, forKey: key)
        }
        UserDefaults.standard.synchronize()

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("AllPatchesDidRestoreNotification"), object: nil)
        }

        return restoredCount
    }

    private static func orderedBundleIdentifiers(in project: PatchProject) -> [String] {
        project.allBundleIdentifiers
    }

    private static func withResolvedContainers<T>(
        bundleIDs: [String],
        operation: ([String: URL]) throws -> T
    ) throws -> T {
        var roots: [String: URL] = [:]

        for bundleID in bundleIDs {
            guard let path = ContainerStore.resolveAppContainerPath(bundleID: bundleID),
                  ContainerStore.isApplicationContainerPath(path) else {
                throw PatchPackageError.targetAppUnavailable(bundleID)
            }
            roots[bundleID] = PatchPathValidator.canonicalFileURL(URL(fileURLWithPath: path, isDirectory: true))
        }
        return try operation(roots)
    }
}
