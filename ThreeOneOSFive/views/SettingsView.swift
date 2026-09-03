import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var appState: AppState
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.english.rawValue
    @AppStorage(FeatureVisibility.cleanerStorageKey) private var cleanerEnabled = true
    @AppStorage(FeatureVisibility.developerModeStorageKey)
    private var developerModeEnabled = false
    @AppStorage("autoRestoreOnExit") private var autoRestoreOnExit = false
    @AppStorage("selected_dns_profile") private var selectedDNS = "nhteam"

    @State private var showRestoreConfirmation = false
    @State private var showRestoreSuccessAlert = false
    @State private var showLogoutConfirmation = false
    @State private var restoredCount = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        AppLogo()

                        VStack(alignment: .leading, spacing: 3) {
                            Text("NH-MOD IOS").font(.headline)
                            Text(language.text("common.version", appVersion))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section(language.text("settings.language")) {
                    Picker(language.text("settings.language"), selection: $languageCode) {
                        ForEach(AppLanguage.allCases) { option in
                            Text(option.displayName).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section {
                    Toggle(isOn: $cleanerEnabled) {
                        Label(language.text("tab.cleaner"), systemImage: "sparkles")
                    }
                    Toggle(isOn: $developerModeEnabled) {
                        Label(
                            language.text("settings.developer_mode"),
                            systemImage: "hammer.fill"
                        )
                    }
                    Toggle(isOn: $autoRestoreOnExit) {
                        Label(
                            language.text("settings.auto_restore_on_exit"),
                            systemImage: "clock.arrow.circlepath"
                        )
                    }
                } header: {
                    Text(language.text("dashboard.features"))
                } footer: {
                    Text(language.text("settings.auto_restore_footer"))
                }

                Section {
                    Button(role: .destructive) {
                        showRestoreConfirmation = true
                    } label: {
                        Label(
                            language.text("settings.clean_restore"),
                            systemImage: "arrow.counterclockwise.circle.fill"
                        )
                        .foregroundStyle(.red)
                    }
                } header: {
                    Text(language.text("tab.cleaner"))
                } footer: {
                    Text(language.text("settings.clean_restore_desc"))
                }

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "shield.checkered")
                                .font(.title3)
                                .foregroundStyle(Color.green)
                            Text(currentDNSProfile.title)
                                .font(.headline)
                            Spacer()
                            Text(currentDNSProfile.id)
                                .font(.caption.monospaced().bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.green.opacity(0.15))
                                .foregroundStyle(Color.green)
                                .clipShape(Capsule())
                        }

                        // Segmented Picker to choose between NH-TEAM VIP and Custom DNS
                        Picker("ជ្រើសរើស DNS", selection: $selectedDNS) {
                            Text("NH-TEAM VIP (1686ae)").tag("nhteam")
                            Text("Custom (1e1e38)").tag("custom")
                        }
                        .pickerStyle(.segmented)
                        .padding(.vertical, 2)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Server URL (\(currentDNSProfile.sourceDesc)):")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(currentDNSProfile.url)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                            }
                            Spacer()
                            Button {
                                UIPasteboard.general.string = currentDNSProfile.url
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.accent)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(8)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .cornerRadius(8)

                        HStack(spacing: 10) {
                            Button {
                                if let url = URL(string: currentDNSProfile.installURL) {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                Label("Install DNS", systemImage: "arrow.down.circle.fill")
                                    .font(.subheadline.bold())
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)

                            Button {
                                if let url = URL(string: "App-Prefs:root=General&path=ManagedConfigurationList") {
                                    if UIApplication.shared.canOpenURL(url) {
                                        UIApplication.shared.open(url)
                                    } else if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                                        UIApplication.shared.open(settingsURL)
                                    }
                                } else if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(settingsURL)
                                }
                            } label: {
                                Label("Settings", systemImage: "gearshape.fill")
                                    .font(.subheadline.bold())
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.top, 2)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("🛡️ ANTI-BAN DNS CONFIGURATION")
                } footer: {
                    Text("អាចប្តូររវាង NH_TEAM_AntiBan_VIP (1686ae) និង Custom DNS (1e1e38) បានតាមចិត្ត រួចចុច Install DNS ដើម្បីដំឡើង Profile ចូលក្នុង Settings (Fix Ban 100%)។")
                }

                if WallpaperFeatureSupportPolicy.isSupported(
                    major: AppInfo.versionTuple.major
                ) {
                    Section {
                        NavigationLink {
                            WallpaperResetSettingsView()
                        } label: {
                            Label(
                                language.text("wallpaper.reset"),
                                systemImage: "arrow.counterclockwise"
                            )
                        }
                    } header: {
                        Text(language.text("tab.wallpapers"))
                    } footer: {
                        Text(language.text("wallpaper.reset_settings_footer"))
                    }
                }

                Section(language.text("common.device")) {
                    LabeledContent(language.text("dashboard.hardware_model"), value: AppInfo.displayMachineName)
                    LabeledContent(language.text("settings.ios_version"), value: "\(AppInfo.osVersion) (\(AppInfo.osBuild))")
                }

                Section {
                    HStack {
                        Text(language.text("settings.current_version"))
                        Spacer()
                        Text(language.text(appState.isSupported ? "settings.supported" : "settings.unsupported"))
                        .foregroundStyle(appState.isSupported ? Color.green : Color.red)
                    }
                    LabeledContent("iOS 17", value: ExploitSupportPolicy.verifiedIOS17Range)
                    LabeledContent("iOS 18", value: ExploitSupportPolicy.verifiedIOS18Range)
                    LabeledContent("iOS 26", value: ExploitSupportPolicy.verifiedIOS26Range)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("iOS 27.0")
                            .font(.body)
                        ForEach(0..<ExploitSupportPolicy.verifiedIOS27Builds.count, id: \.self) { index in
                            Text(versionLabel(ExploitSupportPolicy.verifiedIOS27Builds[index]))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text(language.text("settings.verified_versions"))
                } footer: {
                    Text(language.text("settings.supported_versions_footer"))
                }

                Section(language.text("settings.social_media")) {
                    creditsRow(
                        name: "GitHub",
                        role: language.text("social.github_role"),
                        url: "https://github.com/YangJiiii/3105"
                    )
                    creditsRow(
                        name: "Cộng Đồng IOSVN",
                        role: language.text("social.iosvn_role"),
                        url: "https://t.me/ioscrackvn"
                    )
                }

                Section(language.text("settings.credits")) {
                    creditsRow(
                        name: "YangJiii",
                        role: language.text("credit.yangjiii"),
                        url: "https://x.com/duongduong0908"
                    )
                    creditsRow(
                        name: "0xjohnnydev",
                        role: language.text("credit.filzaslop"),
                        url: "https://github.com/0xjohnnydev/FilzaSlop"
                    )
                    creditsRow(
                        name: "LeminLimez",
                        role: language.text("credit.pocket_poster"),
                        url: "https://github.com/leminlimez/Pocket-Poster"
                    )
                    creditsRow(
                        name: "CrazyMind90",
                        role: language.text("credit.sandbox_escape"),
                        url: "https://github.com/CrazyMind90"
                    )
                    creditsRow(
                        name: "forcequitOS",
                        role: language.text("credit.forcequit"),
                        url: "https://github.com/forcequitOS"
                    )
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        // Header with Key Title and Type Badge
                        HStack {
                            Label("KEY បច្ចុប្បន្ន", systemImage: "key.fill")
                                .font(.headline)
                                .foregroundStyle(.yellow)
                            Spacer()
                            Text(licenseTypeDisplay)
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.yellow.opacity(0.15))
                                .foregroundStyle(.yellow)
                                .clipShape(Capsule())
                        }

                        // Key Value Display Card
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("ACTIVE LICENSE KEY")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text(licenseKeyDisplay)
                                    .font(.system(.body, design: .monospaced).bold())
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                            }
                            Spacer()
                            Button {
                                UIPasteboard.general.string = licenseKeyDisplay
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.accent)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(10)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .cornerRadius(8)

                        // Expiration Display (Days, Hours, Minutes)
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: licenseExpirationInfo.isExpired ? "exclamationmark.circle.fill" : (licenseExpirationInfo.isLifetime ? "infinity" : "clock.fill"))
                                .font(.title3)
                                .foregroundStyle(licenseExpirationInfo.isExpired ? Color.red : (licenseExpirationInfo.isLifetime ? Color.green : Color.orange))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(licenseExpirationInfo.text)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(licenseExpirationInfo.isExpired ? Color.red : (licenseExpirationInfo.isLifetime ? Color.green : Color.orange))
                                Text(licenseExpirationInfo.subText)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .cornerRadius(8)

                        // Logout Button
                        Button(role: .destructive) {
                            showLogoutConfirmation = true
                        } label: {
                            HStack {
                                Spacer()
                                Label("(Logout)", systemImage: "rectangle.portrait.and.arrow.right.fill")
                                    .fontWeight(.bold)
                                    .foregroundStyle(.red)
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("🔑 ព័ត៌មាន LICENSE KEY")
                } footer: {
                    Text("⚠️ Key នេះត្រូវបានភ្ជាប់ជាប់ជាមួយទូរស័ព្ទនេះ (Device ID) រួចរាល់ហើយ។ សូមកុំប្រើប្រាស់ Key ផ្សេង លើកលែងតែ Key នេះផុតកំណត់។")
                }
            }
            .tint(AppTheme.accent)
            .navigationTitle(language.text("settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(language.text("common.done")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .alert(
                language.text("settings.clean_restore_confirm_title"),
                isPresented: $showRestoreConfirmation
            ) {
                Button(language.text("common.cancel"), role: .cancel) {}
                Button(language.text("settings.clean_restore"), role: .destructive) {
                    performRestore()
                }
            } message: {
                Text(language.text("settings.clean_restore_confirm_message"))
            }
            .alert(
                language.text("settings.clean_restore_success_title"),
                isPresented: $showRestoreSuccessAlert
            ) {
                Button(language.text("common.done"), role: .cancel) {}
            } message: {
                Text(language.text("settings.clean_restore_success_message", Int64(restoredCount)))
            }
            .alert("Logout", isPresented: $showLogoutConfirmation) {
                Button("បោះបង់ (Cancel)", role: .cancel) {}
                Button("Logout", role: .destructive) {
                    appState.logout()
                    dismiss()
                }
            } message: {
                Text("តើអ្នកពិតជាចង់ចាកចេញពី Key បច្ចុប្បន្នមែនទេ? អ្នកនឹងត្រូវបញ្ចូល Key សាជាថ្មីដើម្បីចូលប្រើប្រាស់។")
            }
        }
    }

    private func performRestore() {
        do {
            let count = try DevicePatchService.restoreAllAppliedPatches()
            restoredCount = count
            showRestoreSuccessAlert = true
        } catch {
            // Error handling fallback
        }
    }

    private var currentDNSProfile: (title: String, id: String, url: String, installURL: String, sourceDesc: String) {
        if selectedDNS == "nhteam" {
            return (
                title: "NH-TEAM AntiBan VIP",
                id: "1686ae",
                url: "https://dns.nextdns.io/1686ae",
                installURL: "https://apple.nextdns.io/1686ae",
                sourceDesc: "NH_TEAM_AntiBan_VIP.mobileconfig"
            )
        } else {
            return (
                title: "Custom AntiBan DNS",
                id: "1e1e38",
                url: "https://dns.nextdns.io/1e1e38",
                installURL: "https://apple.nextdns.io/1e1e38",
                sourceDesc: "NextDNS Custom Profile"
            )
        }
    }

    private var licenseKeyDisplay: String {
        UserDefaults.standard.string(forKey: "saved_license_key") ?? "N/A"
    }

    private var licenseTypeDisplay: String {
        let type = UserDefaults.standard.string(forKey: "license_key_type") ?? "VIP_ALL"
        switch type {
        case "FF_ONLY": return "🔥 FF ONLY"
        case "MLBB_ONLY": return "⚔️ MLBB ONLY"
        default: return "👑 VIP ALL"
        }
    }

    private var licenseExpirationInfo: (text: String, subText: String, isLifetime: Bool, isExpired: Bool) {
        let raw = UserDefaults.standard.string(forKey: "license_expires_at") ?? "lifetime"
        if raw.lowercased() == "lifetime" || raw.isEmpty {
            return ("គ្មានថ្ងៃផុតកំណត់ (Lifetime ♾️)", "Key នេះអាចប្រើប្រាស់បានជារៀងរហូត", true, false)
        }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var expireDate = formatter.date(from: raw)
        if expireDate == nil {
            let fallbackFormatter = ISO8601DateFormatter()
            expireDate = fallbackFormatter.date(from: raw)
        }
        
        guard let date = expireDate else {
            return ("គ្មានថ្ងៃផុតកំណត់ (Lifetime ♾️)", "Key នេះអាចប្រើប្រាស់បានជារៀងរហូត", true, false)
        }
        
        let now = Date()
        if date <= now {
            return ("បានផុតកំណត់ហើយ (Expired)", "សូមទាក់ទង Admin ដើម្បីបន្តសុពលភាព", false, true)
        }
        
        let diff = Calendar.current.dateComponents([.day, .hour, .minute], from: now, to: date)
        let days = diff.day ?? 0
        let hours = diff.hour ?? 0
        let minutes = diff.minute ?? 0
        
        let remainingString = "សល់ \(days) ថ្ងៃ \(hours) ម៉ោង \(minutes) នាទី"
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "dd/MM/yyyy HH:mm"
        let exactDateStr = "ផុតកំណត់នៅ ៖ " + displayFormatter.string(from: date)
        
        return (remainingString, exactDateStr, false, false)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "AppReleaseDisplayVersion") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.0"
    }

    private func versionLabel(
        _ version: (beta: Int, publicBeta: Int?, build: String)
    ) -> String {
        if let publicBeta = version.publicBeta {
            return language.text(
                "settings.developer_public_beta_build",
                Int64(version.beta),
                Int64(publicBeta),
                version.build
            )
        }
        return language.text(
            "settings.developer_beta_build",
            Int64(version.beta),
            version.build
        )
    }

    @ViewBuilder
    private func creditsRow(name: String, role: String, url: String) -> some View {
        if let destination = URL(string: url) {
            Link(destination: destination) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(role)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 28, height: 28)
                }
                .contentShape(Rectangle())
            }
            .accessibilityLabel(language.text("accessibility.open_profile", name))
        }
    }
}
