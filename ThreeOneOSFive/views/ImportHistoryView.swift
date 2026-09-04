import SwiftUI

struct ImportHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language

    let containerPath: String
    let bundleID: String?
    let onModified: () -> Void

    @State private var records: [ImportedFileRecord] = []
    @State private var isShowingRestoreAllAlert = false
    @State private var isShowingClearHistoryAlert = false
    @State private var selectedRecordForAction: ImportedFileRecord?
    @State private var isPerformingAction = false
    @State private var statusNotice: String?

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: AppTheme.emptyIconSize, weight: .light))
                            .foregroundStyle(.secondary)
                        Text(language.text("browser.import_history_empty"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    List {
                        Section {
                            summaryCard
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)

                        Section(language.text("browser.import_history_title")) {
                            ForEach(records) { record in
                                recordRow(record)
                            }
                        }

                        Section {
                            Button(role: .destructive) {
                                isShowingRestoreAllAlert = true
                            } label: {
                                Label(language.text("browser.clean_restore_title"), systemImage: "arrow.uturn.backward.circle.fill")
                            }
                            .disabled(isPerformingAction)

                            Button {
                                isShowingClearHistoryAlert = true
                            } label: {
                                Label(language.text("browser.clear_history_only"), systemImage: "checkmark.circle")
                            }
                            .disabled(isPerformingAction)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(language.text("browser.import_history_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("common.done")) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                reload()
            }
            .alert(language.text("browser.clean_restore_confirm_title"), isPresented: $isShowingRestoreAllAlert) {
                Button(language.text("common.cancel"), role: .cancel) {}
                Button(language.text("browser.clean_restore_action"), role: .destructive) {
                    performRestoreAll()
                }
            } message: {
                let replaced = records.filter(\.wasReplaced).count
                let added = records.filter { !$0.wasReplaced }.count
                Text(language.text("browser.clean_restore_confirm_message", Int64(replaced), Int64(added)))
            }
            .alert(language.text("browser.clear_history_confirm_title"), isPresented: $isShowingClearHistoryAlert) {
                Button(language.text("common.cancel"), role: .cancel) {}
                Button(language.text("common.ok")) {
                    performClearHistory()
                }
            } message: {
                Text(language.text("browser.clear_history_confirm_message"))
            }
            .alert(
                selectedRecordForAction?.wasReplaced == true
                    ? language.text("browser.restore_file")
                    : language.text("browser.remove_imported_file"),
                isPresented: Binding(
                    get: { selectedRecordForAction != nil },
                    set: { if !$0 { selectedRecordForAction = nil } }
                )
            ) {
                Button(language.text("common.cancel"), role: .cancel) {
                    selectedRecordForAction = nil
                }
                Button(
                    selectedRecordForAction?.wasReplaced == true
                        ? language.text("browser.restore_file")
                        : language.text("common.delete"),
                    role: selectedRecordForAction?.wasReplaced == true ? .none : .destructive
                ) {
                    if let record = selectedRecordForAction {
                        selectedRecordForAction = nil
                        performSingleRecordRestore(record)
                    }
                }
            } message: {
                if let record = selectedRecordForAction {
                    Text(language.text("browser.restore_file_confirm", record.fileName))
                }
            }
            .overlay {
                if isPerformingAction {
                    ZStack {
                        Color.black.opacity(0.35).ignoresSafeArea()
                        ProgressView(language.text("browser.clean_restore_progress"))
                            .padding()
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }

    private var summaryCard: some View {
        let replaced = records.filter(\.wasReplaced).count
        let added = records.filter { !$0.wasReplaced }.count

        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(language.text("browser.tracking_banner_both", Int64(replaced), Int64(added)))
                    .font(.headline)
                Text(language.text("browser.clean_restore_subtitle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color.accentColor)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func recordRow(_ record: ImportedFileRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: record.wasReplaced ? "arrow.triangle.2.circlepath" : "doc.badge.plus")
                .font(.title3)
                .foregroundStyle(record.wasReplaced ? Color.accentColor : Color.green)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.fileName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                Text(record.relativePath)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(record.wasReplaced ? language.text("browser.status_replaced") : language.text("browser.status_added"))
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            record.wasReplaced
                                ? Color.blue.opacity(0.15)
                                : Color.green.opacity(0.15)
                        )
                        .foregroundStyle(record.wasReplaced ? Color.blue : Color.green)
                        .clipShape(Capsule())

                    if let size = record.originalFileSize, record.wasReplaced {
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(record.importedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 2)
            }

            Button {
                selectedRecordForAction = record
            } label: {
                Image(systemName: record.wasReplaced ? "arrow.uturn.backward.circle" : "trash")
                    .font(.title3)
                    .foregroundStyle(record.wasReplaced ? Color.accentColor : Color.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private func reload() {
        records = ImportBackupManager.shared.records(containerPath: containerPath, bundleID: bundleID)
    }

    private func performRestoreAll() {
        isPerformingAction = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let summary = try ImportBackupManager.shared.restoreAndCleanAll(
                    containerPath: containerPath,
                    bundleID: bundleID
                )
                log("ImportHistoryView: restored \(summary.restoredOriginalsCount) files, removed \(summary.removedNewFilesCount) files")
                DispatchQueue.main.async {
                    isPerformingAction = false
                    reload()
                    onModified()
                }
            } catch {
                log("ImportHistoryView: restore failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    isPerformingAction = false
                    reload()
                    onModified()
                }
            }
        }
    }

    private func performClearHistory() {
        isPerformingAction = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try ImportBackupManager.shared.commitAsNewOriginals(
                    containerPath: containerPath,
                    bundleID: bundleID
                )
                DispatchQueue.main.async {
                    isPerformingAction = false
                    reload()
                    onModified()
                }
            } catch {
                DispatchQueue.main.async {
                    isPerformingAction = false
                    reload()
                    onModified()
                }
            }
        }
    }

    private func performSingleRecordRestore(_ record: ImportedFileRecord) {
        isPerformingAction = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try ImportBackupManager.shared.restoreSingleRecord(
                    record,
                    containerPath: containerPath,
                    bundleID: bundleID
                )
                DispatchQueue.main.async {
                    isPerformingAction = false
                    reload()
                    onModified()
                }
            } catch {
                DispatchQueue.main.async {
                    isPerformingAction = false
                    reload()
                    onModified()
                }
            }
        }
    }
}
