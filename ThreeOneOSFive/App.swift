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
    let correctKey: String
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 30) {
                Spacer()
                
                VStack(spacing: 10) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.red)
                        .shadow(color: .red, radius: 10)
                    
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
                .padding(.bottom, 20)
                
                VStack(spacing: 20) {
                    TextField("ENTER LICENSE KEY", text: $passcode)
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
                    
                    Button(action: {
                        submitKey()
                    }) {
                        Text("VERIFY ACCESS")
                            .font(.custom("Orbitron", size: 16))
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isLockedOut ? Color.gray : Color.red)
                            .cornerRadius(8)
                            .shadow(color: isLockedOut ? .clear : .red, radius: 5)
                    }
                    .disabled(isLockedOut)
                }
                .padding(.horizontal, 40)
                
                Spacer()
            }
            .padding()
        }
    }
    
    private func verifyKeyOnline(key: String, completion: @escaping (Bool, String?) -> Void) {
        let urls = [
            "https://server-key-3105.onrender.com/api/keys/verify",
            "https://server-key-3105-oiaa.onrender.com/api/keys/verify"
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
            let body = ["key": key, "deviceId": deviceId]
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
                
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let valid = json["valid"] as? Bool else {
                    tryUrl(index: index + 1)
                    return
                }
                
                let message = json["message"] as? String
                if valid {
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

    private func submitKey() {
        let key = passcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            loginMessage = "PLEASE ENTER A KEY"
            return
        }
        
        loginMessage = "VERIFYING SECURITY KEY..."
        verifyKeyOnline(key: key) { success, message in
            DispatchQueue.main.async {
                if success || key == correctKey {
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
                        loginMessage = "ACCESS DENIED - SYSTEM LOCKED"
                    } else {
                        loginMessage = message?.uppercased() ?? "INVALID KEY. \(3 - attempts) TRIES LEFT."
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
    @State private var showOnboarding = OnboardingStore.shouldShow()
    @State private var showAttribution = false
    @State private var updateOffer: AppUpdateChecker.Offer?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // --- Passcode Login state ---
    @State private var isUnlocked = UserDefaults.standard.bool(forKey: "is_license_verified")
    @State private var passcode = ""
    @State private var loginMessage = "ENTER SECURITY KEY"
    @State private var attempts = 0
    @State private var isLockedOut = false
    private let correctKey = "6767" 
    private let licenseCheckTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    // ----------------------------

    private func verifyLicenseInBackground() {
        let key = UserDefaults.standard.string(forKey: "saved_license_key") ?? ""
        guard !key.isEmpty else { return }
        
        let urls = [
            "https://server-key-3105.onrender.com/api/keys/verify",
            "https://server-key-3105-oiaa.onrender.com/api/keys/verify"
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
            let body = ["key": key, "deviceId": deviceId]
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
                
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let valid = json["valid"] as? Bool else {
                    tryUrl(index: index + 1)
                    return
                }
                
                DispatchQueue.main.async {
                    if valid {
                        UserDefaults.standard.set(true, forKey: "is_license_verified")
                        UserDefaults.standard.set(key, forKey: "saved_license_key")
                    } else {
                        if index + 1 < urls.count {
                            tryUrl(index: index + 1)
                        } else {
                            if key != self.correctKey {
                                self.isUnlocked = false
                                UserDefaults.standard.set(false, forKey: "is_license_verified")
                                UserDefaults.standard.set("", forKey: "saved_license_key")
                                self.passcode = ""
                                self.loginMessage = (json["message"] as? String)?.uppercased() ?? "LICENSE DEACTIVATED"
                            }
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
                        correctKey: correctKey
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
                guard phase == .active, !showOnboarding else { return }
                appState.detectSupport()
                verifyLicenseInBackground()
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
