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
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 30) {
                Spacer()
                
                VStack(spacing: 14) {
                    Image("AppIcon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 85, height: 85)
                        .cornerRadius(18)
                        .shadow(color: .red.opacity(0.6), radius: 12)
                    
                    Text("COBALT SHIELD")
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
            "https://server-key-3105-oiaa.onrender.com/api/keys/verify",
            "https://server-key-3105.onrender.com/api/keys/verify"
        ]
        
        func tryUrl(index: Int) {
            guard index < urls.count else {
                completion(false, "CONNECTION FAILED")
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
            let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.1"
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

    // --- Passcode Login state ---
    @State private var isUnlocked = UserDefaults.standard.bool(forKey: "is_license_verified")
    @State private var passcode = ""
    @State private var loginMessage = "សូមបញ្ចូល KEY សម្រាប់ចូលប្រើប្រាស់"
    @State private var attempts = 0
    @State private var isLockedOut = false
    private let licenseCheckTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    // ----------------------------

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
        guard !key.isEmpty else { return }
        
        let urls = [
            "https://server-key-3105-oiaa.onrender.com/api/keys/verify",
            "https://server-key-3105.onrender.com/api/keys/verify"
        ]
        
        func tryUrl(index: Int) {
            guard index < urls.count else { return }
            guard let url = URL(string: urls[index]) else {
                tryUrl(index: index + 1)
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
            let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.1"
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
                    self.showForcedUpdateAlert(message: msg)
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
                    } else {
                        if index + 1 < urls.count {
                            tryUrl(index: index + 1)
                        } else {
                            self.isUnlocked = false
                            UserDefaults.standard.set(false, forKey: "is_license_verified")
                            UserDefaults.standard.set("", forKey: "saved_license_key")
                            UserDefaults.standard.set("", forKey: "download_token")
                            self.passcode = ""
                            self.loginMessage = (json["message"] as? String)?.uppercased() ?? "LICENSE DEACTIVATED"
                        }
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
                        onForcedUpdateRequired: showForcedUpdateAlert
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
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active, !showOnboarding {
                    appState.detectSupport()
                    verifyLicenseInBackground()
                } else if (phase == .background || phase == .inactive) && autoRestoreOnExit {
                    try? DevicePatchService.restoreAllAppliedPatches()
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
                    try? DevicePatchService.restoreAllAppliedPatches()
                }
            }
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
