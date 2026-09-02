import SwiftUI
import UIKit
import Combine

// Custom Passcode Login view
struct CyberLoginView: View {
    @Binding var passcode: String
    @Binding var loginMessage: String
    @Binding var isUnlocked: Bool
    @Binding var attempts: Int
    @Binding var isLockedOut: Bool
    let onForcedUpdateRequired: (String) -> Void
    let onNoInternetOrServerDown: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 30) {
                Spacer()
                
                VStack(spacing: 14) {
                    Image("HackerIcon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 85, height: 85)
                        .cornerRadius(18)
                        .shadow(color: .red.opacity(0.6), radius: 12)
                    
                    Text("សួស្ដីអ្នកទាំងអស់គ្នា")
                        .font(.custom("Orbitron", size: 24))
                        .fontWeight(.black)
                        .foregroundColor(.white)
                    
                    Text(loginMessage)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.red.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.bottom, 10)
                
                VStack(spacing: 20) {
                    SecureField("បញ្ចូល KEY ចូលប្រើប្រាស់...", text: $passcode)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(8)
                        .foregroundColor(.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
                        )
                        .multilineTextAlignment(.center)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .disabled(isLockedOut)
                        .onChange(of: passcode) { newValue in
                            let cleaned = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !cleaned.isEmpty && !isLockedOut {
                                submitKey(keyToVerify: cleaned)
                            }
                        }
                }
                .padding(.horizontal, 40)
                
                Spacer()
            }
            .padding()
        }
    }
    
    private func verifyKeyOnline(key: String, completion: @escaping (Bool, String?) -> Void) {
        let urls = [
            "https://server-key-3105-6sbz.onrender.com/api/keys/verify",
            "https://server-key-3105-oiaa.onrender.com/api/keys/verify",
            "https://server-key-3105.onrender.com/api/keys/verify"
        ]
        
        func tryUrl(index: Int) {
            guard index < urls.count else {
                completion(false, "CONNECTION FAILED")
                DispatchQueue.main.async {
                    onNoInternetOrServerDown()
                }
                return
            }
            guard let url = URL(string: urls[index]) else {
                tryUrl(index: index + 1)
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
            let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.2"
            let body = ["key": key, "deviceId": deviceId, "version": appVersion]
            guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
                tryUrl(index: index + 1)
                return
            }
            request.httpBody = jsonData
            
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if error != nil {
                    tryUrl(index: index + 1)
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    tryUrl(index: index + 1)
                    return
                }
                
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    tryUrl(index: index + 1)
                    return
                }
                
                if let updateRequired = json["updateRequired"] as? Bool, updateRequired {
                    let msg = json["message"] as? String ?? "App needs to update to new version"
                    onForcedUpdateRequired(msg)
                    return
                }
                
                guard let valid = json["valid"] as? Bool else {
                    tryUrl(index: index + 1)
                    return
                }
                
                let message = json["message"] as? String
                let downloadToken = json["downloadToken"] as? String
                if valid {
                    if let downloadToken = downloadToken {
                        UserDefaults.standard.set(downloadToken, forKey: "download_token")
                    }
                    if let keyType = json["keyType"] as? String {
                        UserDefaults.standard.set(keyType, forKey: "license_key_type")
                    }
                    if let allowedGames = json["allowedGames"] as? [String] {
                        UserDefaults.standard.set(allowedGames, forKey: "license_allowed_games")
                    }
                    if let expiresAt = json["expiresAt"] as? String {
                        UserDefaults.standard.set(expiresAt, forKey: "license_expires_at")
                    } else {
                        UserDefaults.standard.set("lifetime", forKey: "license_expires_at")
                    }
                    completion(true, message)
                } else {
                    if index + 1 < urls.count {
                        tryUrl(index: index + 1)
                    } else {
                        completion(false, message)
                    }
                }
            }
            task.resume()
        }
        
        tryUrl(index: 0)
    }

    @State private var isVerifying = false

    private func submitKey(keyToVerify: String? = nil) {
        let key = (keyToVerify ?? passcode).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !isVerifying else { return }
        
        isVerifying = true
        loginMessage = "កំពុងផ្ទៀងផ្ទាត់ KEY..."
        verifyKeyOnline(key: key) { success, message in
            DispatchQueue.main.async {
                isVerifying = false
                if success {
                    UserDefaults.standard.set(true, forKey: "is_license_verified")
                    UserDefaults.standard.set(key, forKey: "saved_license_key")
                    withAnimation(.easeInOut) {
                        isUnlocked = true
                    }
                } else {
                    attempts += 1
                    passcode = ""
                    if attempts >= 3 {
                        isLockedOut = true
                        loginMessage = "ប្រព័ន្ធត្រូវបានចាក់សោ - ACCESS DENIED"
                    } else {
                        loginMessage = message?.uppercased() ?? "KEY មិនត្រឹមត្រូវ! សល់ការសាកល្បង \(3 - attempts) លើកទៀត"
                    }
                }
            }
        }
    }
}

@main
struct ThreeOneOSFiveApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var patchDraftCoordinator = PatchDraftCoordinator()
    @StateObject private var fileOperationCoordinator = FileOperationCoordinator()
    @StateObject private var patchStore = PatchProjectStore()
    @StateObject private var repositoryStore = PackageRepositoryStore()
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.english.rawValue
    @AppStorage("autoRestoreOnExit") private var autoRestoreOnExit = false
    @State private var showOnboarding = OnboardingStore.shouldShow()
    @State private var showAttribution = false
    @State private var updateOffer: AppUpdateChecker.Offer?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // --- Passcode Login & Announcement state ---
    @State private var isUnlocked = UserDefaults.standard.bool(forKey: "is_license_verified")
    @State private var passcode = ""
    @State private var loginMessage = "សូមបញ្ចូល KEY សម្រាប់ចូលប្រើប្រាស់"
    @State private var attempts = 0
    @State private var isLockedOut = false
    @State private var activeAnnouncement: AnnouncementItem? = nil
    private let licenseCheckTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    // ----------------------------

    private func showNoInternetAndExitAlert(message: String = "គ្មានការតភ្ជាប់អ៊ីនធឺណិត ឬ Server ឈប់ដំណើរការ!") {
        DispatchQueue.main.async {
            let alert = UIAlertController(
                title: "គ្មាន INTERNET",
                message: message,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "ចាកចេញពី App (OK)", style: .destructive) { _ in
                exit(0)
            })
            
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = scene.windows.first {
                var topVC = window.rootViewController
                while let presented = topVC?.presentedViewController {
                    topVC = presented
                }
                topVC?.present(alert, animated: true, completion: nil)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    exit(0)
                }
            }
        }
    }

    private func showForcedUpdateAlert(message: String) {
        DispatchQueue.main.async {
            let alert = UIAlertController(
                title: "Update",
                message: message,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                exit(0)
            })
            
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = scene.windows.first {
                var topVC = window.rootViewController
                while let presented = topVC?.presentedViewController {
                    topVC = presented
                }
                topVC?.present(alert, animated: true, completion: nil)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    exit(0)
                }
            }
        }
    }

    private func verifyLicenseInBackground() {
        let key = UserDefaults.standard.string(forKey: "saved_license_key") ?? ""
        
        let urls = [
            "https://server-key-3105-6sbz.onrender.com/api/keys/verify",
            "https://server-key-3105-oiaa.onrender.com/api/keys/verify",
            "https://server-key-3105.onrender.com/api/keys/verify"
        ]
        
        func tryUrl(index: Int) {
            guard index < urls.count else {
                // Connection failed for all servers (No internet connection or Server down)
                self.showNoInternetAndExitAlert(message: "គ្មានការតភ្ជាប់អ៊ីនធឺណិត ឬ Server ឈប់ដំណើរការ!")
                return
            }
            guard let url = URL(string: urls[index]) else {
                tryUrl(index: index + 1)
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 8.0
            
            let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
            let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.2"
            let body = ["key": key.isEmpty ? "PING_CHECK" : key, "deviceId": deviceId, "version": appVersion]
            guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
                tryUrl(index: index + 1)
                return
            }
            request.httpBody = jsonData
            
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if error != nil {
                    tryUrl(index: index + 1)
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    tryUrl(index: index + 1)
                    return
                }
                
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    tryUrl(index: index + 1)
                    return
                }
                
                if let updateRequired = json["updateRequired"] as? Bool, updateRequired {
                    let msg = json["message"] as? String ?? "App needs to update to new version"
                    self.showForcedUpdateAlert(message: msg)
                    return
                }
                
                guard !key.isEmpty else {
                    // Launch ping check passed
                    return
                }
                
                guard let valid = json["valid"] as? Bool else {
                    tryUrl(index: index + 1)
                    return
                }
                
                DispatchQueue.main.async {
                    if valid {
                        UserDefaults.standard.set(true, forKey: "is_license_verified")
                        UserDefaults.standard.set(key, forKey: "saved_license_key")
                        if let downloadToken = json["downloadToken"] as? String {
                            UserDefaults.standard.set(downloadToken, forKey: "download_token")
                        }
                        if let expiresAt = json["expiresAt"] as? String {
                            UserDefaults.standard.set(expiresAt, forKey: "license_expires_at")
                        } else {
                            UserDefaults.standard.set("lifetime", forKey: "license_expires_at")
                        }
                    } else {
                        // LICENSE EXPIRED OR DEACTIVATED!
                        // Auto restore all applied MOD patches back to original files!
                        _ = try? DevicePatchService.restoreAllAppliedPatches()
                        
                        self.isUnlocked = false
                        UserDefaults.standard.set(false, forKey: "is_license_verified")
                        UserDefaults.standard.set("", forKey: "saved_license_key")
                        UserDefaults.standard.set("", forKey: "download_token")
                        self.passcode = ""
                        self.loginMessage = (json["message"] as? String)?.uppercased() ?? "LICENCE KEY អស់សុពលភាព - ឯកសារដើមត្រូវបាន RESTORE AUTO"
                    }
                }
            }
            task.resume()
        }
        
        tryUrl(index: 0)
    }

    init() {
        setupLogCapture()
        log("app: 3105 launching — iOS \(AppInfo.osVersion) (\(AppInfo.osBuild)) \(AppInfo.machineName)")
        UserDefaults.standard.set(true, forKey: "feature.developer_mode.enabled")
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: languageCode) ?? .english
    }

    private func checkForUpdate() {
        Task {
            guard let offer = await AppUpdateChecker.check() else { return }
            await MainActor.run { updateOffer = offer }
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if isUnlocked {
                    ZStack {
                        ContentView()
                            .environmentObject(appState)
                            .environmentObject(patchDraftCoordinator)
                            .environmentObject(fileOperationCoordinator)
                            .environmentObject(patchStore)
                            .environmentObject(repositoryStore)
                            .environment(\.appLanguage, language)
                            .environment(\.locale, language.locale)
                            .opacity(showOnboarding ? 0 : 1)
                            .allowsHitTesting(!showOnboarding)

                        if showOnboarding {
                            OnboardingView {
                                OnboardingStore.markCompleted()
                                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
                                    showOnboarding = false
                                }
                                appState.detectSupport()
                                checkForUpdate()
                            }
                            .environment(\.appLanguage, language)
                            .environment(\.locale, language.locale)
                            .transition(
                                reduceMotion
                                    ? .opacity
                                    : .opacity.combined(with: .scale(scale: 0.98))
                            )
                            .zIndex(1)
                        }
                    }
                } else {
                    CyberLoginView(
                        passcode: $passcode,
                        loginMessage: $loginMessage,
                        isUnlocked: $isUnlocked,
                        attempts: $attempts,
                        isLockedOut: $isLockedOut,
                        onForcedUpdateRequired: showForcedUpdateAlert,
                        onNoInternetOrServerDown: {
                            showNoInternetAndExitAlert(message: "គ្មានការតភ្ជាប់អ៊ីនធឺណិត ឬ Server ឈប់ដំណើរការ!")
                        }
                    )
                }
            }
            .displayIdentityAttribution(isPresented: $showAttribution, enabled: !showOnboarding && isUnlocked)
            .sheet(isPresented: $showAttribution) {
                DisplayAttributionSheet()
            }
            .alert(item: $updateOffer) { offer in
                Alert(
                    title: Text(language.text("update.title")),
                    message: Text(language.text("update.message", offer.version)),
                    primaryButton: .default(Text(language.text("update.agree"))) {
                        UIApplication.shared.open(offer.url)
                    },
                    secondaryButton: .cancel(Text(language.text("update.dismiss"))) {
                        AppUpdateChecker.dismiss(version: offer.version)
                    }
                )
            }
            .onAppear {
                if !showOnboarding {
                    appState.detectSupport()
                    checkForUpdate()
                }
                verifyLicenseInBackground()
                fetchAnnouncementConfig()
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active, !showOnboarding {
                    appState.detectSupport()
                    verifyLicenseInBackground()
                    fetchAnnouncementConfig()
                }
            }
            .onOpenURL { url in
                if isUnlocked {
                    patchDraftCoordinator.presentImport(url)
                }
            }
            .onReceive(licenseCheckTimer) { _ in
                if isUnlocked {
                    verifyLicenseInBackground()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                if autoRestoreOnExit {
                    _ = try? DevicePatchService.restoreAllAppliedPatches()
                }
            }
            .overlay {
                if let ann = activeAnnouncement {
                    CyberAnnouncementView(item: ann) {
                        UserDefaults.standard.set(ann.id, forKey: "last_dismissed_announcement_id")
                        withAnimation {
                            self.activeAnnouncement = nil
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
        }
    }

    private func fetchAnnouncementConfig() {
        let urls = [
            "https://server-key-3105-6sbz.onrender.com/api/config",
            "https://server-key-3105-oiaa.onrender.com/api/config",
            "https://server-key-3105.onrender.com/api/config"
        ]
        
        func tryConfig(index: Int) {
            guard index < urls.count else { return }
            guard let url = URL(string: urls[index]) else {
                tryConfig(index: index + 1)
                return
            }
            URLSession.shared.dataTask(with: url) { data, response, _ in
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    tryConfig(index: index + 1)
                    return
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    tryConfig(index: index + 1)
                    return
                }
                
                let enabled = json["announcement_enabled"] as? String ?? "false"
                let title = json["announcement_title"] as? String ?? "📢 ប្រកាសព័ត៌មានអាប់ដេត"
                let message = json["announcement_message"] as? String ?? ""
                let annId = json["announcement_id"] as? String ?? "1"
                
                if enabled == "true" && !message.isEmpty {
                    let lastDismissed = UserDefaults.standard.string(forKey: "last_dismissed_announcement_id")
                    if lastDismissed != annId {
                        DispatchQueue.main.async {
                            withAnimation {
                                self.activeAnnouncement = AnnouncementItem(id: annId, title: title, message: message)
                            }
                        }
                    }
                }
            }.resume()
        }
        
        tryConfig(index: 0)
    }
}

struct AnnouncementItem: Identifiable {
    let id: String
    let title: String
    let message: String
}

struct CyberAnnouncementView: View {
    let item: AnnouncementItem
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            
            VStack(spacing: 18) {
                Image(systemName: "megaphone.fill")
                    .font(.system(size: 45))
                    .foregroundStyle(.yellow)
                    .shadow(color: .yellow.opacity(0.5), radius: 8)
                    .padding(.top, 8)
                
                Text(item.title)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text(item.message)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                
                Button(action: onDismiss) {
                    Text("យល់ព្រម / OK")
                        .font(.headline.weight(.bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.yellow)
                        .cornerRadius(12)
                }
                .padding(.top, 8)
            }
            .padding(24)
            .background(Color(red: 0.08, green: 0.10, blue: 0.18))
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.yellow.opacity(0.5), lineWidth: 1.5)
            )
            .padding(.horizontal, 28)
            .shadow(color: .yellow.opacity(0.25), radius: 20)
        }
    }
}

class AppState: ObservableObject {
    @Published var exploitStatus: ExploitStatus = .notStarted
    @Published var unsupportedMessage: String?
    @Published var kernelExploitRunning = false

    private var autoRunAttempted = false

    var kernelExploitApplicable: Bool {
        KernelExploit.isApplicable(
            major: AppInfo.versionTuple.major,
            minor: AppInfo.versionTuple.minor,
            patch: AppInfo.versionTuple.patch,
            build: AppInfo.osBuild
        )
    }

    var isSupported: Bool { unsupportedMessage == nil }

    func detectSupport() {
        let v = AppInfo.versionTuple
        let supported = ExploitSupportPolicy.isSupported(
            major: v.major,
            minor: v.minor,
            patch: v.patch,
            build: AppInfo.osBuild
        )
#if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--simulate-access") {
            exploitStatus = .success(method: "Simulator preview")
        }
#endif

        unsupportedMessage = supported ? nil : "iOS \(AppInfo.osVersion) (\(AppInfo.osBuild))"
        if let unsupportedMessage {
            exploitStatus = .unsupported(unsupportedMessage)
            return
        }

        let applicable = KernelExploit.isApplicable(
            major: v.major,
            minor: v.minor,
            patch: v.patch,
            build: AppInfo.osBuild
        )
        guard applicable else { return }

        refreshKernelExploitStatus()
        maybeAutoRunKernelExploit()
    }

    private func maybeAutoRunKernelExploit() {
        guard !kernelExploitRunning,
              !exploitStatus.isSuccess,
              !exploitStatus.isFailed,
              !autoRunAttempted else { return }
        autoRunAttempted = true
        log("app: starting kernel exploit automatically")
        runKernelExploitIfNeeded()
    }

    private func refreshKernelExploitStatus() {
        guard !kernelExploitRunning else { return }

        // iOS < 26: kernel R/W success persists (no sandbox probe)
        // iOS >= 26: verify full sandbox escape is still active
        if KernelExploit.requiresSandboxEscape {
            if KernelExploit.hasSandboxAccess() {
                if !exploitStatus.isSuccess {
                    exploitStatus = .success(method: "kexploit")
                    log("app: existing sandbox access is still active; skipping kernel exploit")
                }
            } else if exploitStatus.isSuccess {
                exploitStatus = .notStarted
                log("app: sandbox access is no longer active")
            }
        }
    }

    func runKernelExploitIfNeeded() {
        refreshKernelExploitStatus()
        guard !kernelExploitRunning,
              !exploitStatus.isSuccess,
              !exploitStatus.isFailed else { return }
        kernelExploitRunning = true
        exploitStatus = .notStarted
        log("app: running kernel exploit on background...")
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = KernelExploit.run()
            DispatchQueue.main.async {
                self.kernelExploitRunning = false
                if ok {
                    self.exploitStatus = .success(method: "kexploit")
                    if KernelExploit.requiresSandboxEscape {
                        log("app: kernel exploit success — sandbox access verified")
                    } else {
                        log("app: kernel exploit success — kernel access active")
                    }
                } else {
                    self.exploitStatus = .failed(method: "kexploit", code: -1)
                    log("app: kernel exploit failed — relaunch the app before retrying")
                }
            }
        }
    }
}
