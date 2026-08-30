import SwiftUI
import UIKit

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
                    Image(systemName: "lock.shield.fill")
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
                }
                
                HStack(spacing: 20) {
                    ForEach(0..<4, id: \.self) { i in
                        Circle()
                            .fill(i < passcode.count ? Color.red : Color.gray.opacity(0.3))
                            .frame(width: 15, height: 15)
                            .shadow(color: i < passcode.count ? .red : .clear, radius: 5)
                    }
                }
                .padding(.vertical, 20)
                
                VStack(spacing: 15) {
                    let keys = [
                        ["1", "2", "3"],
                        ["4", "5", "6"],
                        ["7", "8", "9"],
                        ["CLR", "0", "ENT"]
                    ]
                    
                    ForEach(keys, id: \.self) { row in
                        HStack(spacing: 20) {
                            ForEach(row, id: \.self) { key in
                                Button(action: {
                                    pressKey(key)
                                }) {
                                    Text(key)
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .frame(width: 75, height: 75)
                                        .background(Color.white.opacity(0.05))
                                        .foregroundColor(key == "CLR" ? .red : (key == "ENT" ? .green : .white))
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle().stroke(Color.white.opacity(0.1), lineWidth: 1)
                                        )
                                }
                                .disabled(isLockedOut)
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
        }
    }
    
    private func pressKey(_ key: String) {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        if key == "CLR" {
            passcode = ""
            loginMessage = "ENTER SECURITY KEY"
        } else if key == "ENT" {
            if passcode == correctKey {
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
                    loginMessage = "INVALID KEY. \(3 - attempts) TRIES LEFT."
                }
            }
        } else {
            if passcode.count < 4 {
                passcode += key
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
    @State private var isUnlocked = false
    @State private var passcode = ""
    @State private var loginMessage = "ENTER SECURITY KEY"
    @State private var attempts = 0
    @State private var isLockedOut = false
    private let correctKey = "6767" 
    // ----------------------------

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
            }
            .onChange(of: scenePhase) { phase in
                guard phase == .active, !showOnboarding else { return }
                appState.detectSupport()
                if phase == .background {
                    isUnlocked = false
                    passcode = ""
                    loginMessage = "ENTER SECURITY KEY"
                }
            }
            .onOpenURL { url in
                if isUnlocked {
                    patchDraftCoordinator.presentImport(url)
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
