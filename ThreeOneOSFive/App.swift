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
