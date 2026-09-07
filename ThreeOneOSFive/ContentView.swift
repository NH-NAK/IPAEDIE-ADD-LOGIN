import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var patchDraftCoordinator: PatchDraftCoordinator
    @EnvironmentObject private var patchStore: PatchProjectStore
    @EnvironmentObject private var repositoryStore: PackageRepositoryStore
    @AppStorage(FeatureVisibility.developerModeStorageKey)
    private var developerModeEnabled = false
    @State private var tabNavigation: AppTabNavigationState
    @State private var showSettings = false
    @State private var showLogs = false

    init() {
#if targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        let initialTab: Int
        if arguments.contains("--simulate-new-tab") {
            initialTab = 1
        } else if arguments.contains("--simulate-sources-tab") {
            initialTab = 2
        } else if arguments.contains("--simulate-installed-tab")
                    || arguments.contains("--simulate-patch-tab")
                    || arguments.contains("--simulate-wallpaper-tab") {
            initialTab = 3
        } else if arguments.contains("--simulate-files-tab") {
            initialTab = 4
        } else if arguments.contains("--simulate-search-tab") {
            initialTab = 5
        } else {
            initialTab = 0
        }
        _tabNavigation = State(initialValue: AppTabNavigationState(selectedTab: initialTab))
        _showSettings = State(
            initialValue: arguments.contains("--simulate-settings")
        )
#else
        _tabNavigation = State(initialValue: AppTabNavigationState())
#endif
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .tint(AppTheme.accent)
        .imageScale(.small)
        .onChange(of: patchDraftCoordinator.request?.id) { requestID in
            if requestID != nil { tabNavigation.select(AppSection.installed.rawValue) }
        }
        .onChange(of: patchDraftCoordinator.importRequest?.id) { requestID in
            if requestID != nil { tabNavigation.select(AppSection.installed.rawValue) }
        }
        .onChange(of: developerModeEnabled) { _ in
            tabNavigation.reconcileSelection(with: featureVisibility)
        }
        .onAppear {
            tabNavigation.reconcileSelection(with: featureVisibility)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showLogs) { LogView() }
        .patchStorePresentation(patchStore)
        .repositoryStorePresentation(repositoryStore, patchStore: patchStore)
        .overlay {
            FloatingOverlayMenuView()
        }
    }

    private var compactLayout: some View {
        TabView(selection: tabSelection) {
            ForEach(featureVisibility.visibleSections) { section in
                sectionContent(section)
                    .tabItem {
                        CompactTabLabel(
                            title: language.text(section.titleKey),
                            systemImage: section.systemImage
                        )
                    }
                    .tag(section.rawValue)
            }
        }
    }

    private var regularLayout: some View {
        NavigationSplitView {
            List {
                ForEach(featureVisibility.visibleSections) { section in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            tabNavigation.select(section.rawValue)
                        }
                    } label: {
                        Label(language.text(section.titleKey), systemImage: section.systemImage)
                            .fontWeight(section.rawValue == tabNavigation.selectedTab ? .semibold : .regular)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        section.rawValue == tabNavigation.selectedTab
                            ? AppTheme.accent.opacity(0.14)
                            : Color.clear
                    )
                    .accessibilityAddTraits(
                        section.rawValue == tabNavigation.selectedTab ? .isSelected : []
                    )
                }
            }
            .navigationTitle("NH-MOD IOS")
            .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            sectionContent(selectedVisibleSection)
                .id(selectedVisibleSection.rawValue)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func sectionContent(_ section: AppSection) -> some View {
        switch section {
        case .home:
            RepositoryHomeView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        case .new:
            RepositoryNewView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        case .sources:
            RepositorySourcesView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        case .installed:
            PatchProjectsView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        case .files:
            AppDataBrowserView(
                tabSession: filesTabSession,
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        case .search:
            RepositorySearchView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        }
    }

    private var tabSelection: Binding<Int> {
        Binding(
            get: { tabNavigation.selectedTab },
            set: { tabNavigation.select($0) }
        )
    }

    private var filesTabSession: Binding<FilesTabSession> {
        Binding(
            get: { tabNavigation.filesTabs },
            set: { tabNavigation.setFilesTabs($0) }
        )
    }

    private var featureVisibility: FeatureVisibility {
        FeatureVisibility(developerModeEnabled: developerModeActive)
    }

    private var developerModeActive: Bool {
#if targetEnvironment(simulator)
        developerModeEnabled
            || ProcessInfo.processInfo.arguments.contains("--simulate-developer-mode")
            || ProcessInfo.processInfo.arguments.contains("--simulate-files-tab")
#else
        developerModeEnabled
#endif
    }

    private var selectedVisibleSection: AppSection {
        let selected = AppSection(rawValue: tabNavigation.selectedTab)
        return selected.flatMap {
            featureVisibility.isVisible($0) ? $0 : nil
        } ?? .home
    }

    private func openSettings() {
        showSettings = true
    }

    private func openLogs() {
        showLogs = true
    }
    
}

private struct CompactTabLabel: View {
    let title: String
    let systemImage: String

    @ViewBuilder
    var body: some View {
        if let image = UIImage(
            systemName: systemImage,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        )?.withRenderingMode(.alwaysTemplate) {
            Image(uiImage: image)
        } else {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
        }
        Text(title)
    }
}

private extension AppSection {
    var titleKey: String {
        switch self {
        case .home: return "tab.home"
        case .new: return "tab.new"
        case .sources: return "tab.sources"
        case .installed: return "tab.installed"
        case .files: return "tab.files"
        case .search: return "tab.search"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .new: return "clock.fill"
        case .sources: return "shippingbox.fill"
        case .installed: return "tray.full.fill"
        case .files: return "folder.fill"
        case .search: return "magnifyingglass"
        }
    }
}

// MARK: - Floating Overlay Menu View

struct FloatingOverlayMenuView: View {
    @AppStorage("feature.floating_menu.enabled") private var floatingMenuEnabled = false
    @EnvironmentObject private var patchStore: PatchProjectStore
    @EnvironmentObject private var repositoryStore: PackageRepositoryStore
    
    @State private var isMenuOpen = false
    @State private var position: CGPoint = CGPoint(x: UIScreen.main.bounds.width - 38, y: 320)
    @State private var dragOffset: CGSize = .zero
    @State private var activeCount: Int = 0
    
    private var currentPosition: CGPoint {
        CGPoint(x: position.x + dragOffset.width, y: position.y + dragOffset.height)
    }

    var body: some View {
        if floatingMenuEnabled {
            GeometryReader { proxy in
                let screenSize = proxy.size
                ZStack {
                    if isMenuOpen {
                        // Dimmed backdrop
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                            .transition(.opacity)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    isMenuOpen = false
                                }
                            }
                        
                        // Floating Menu Card
                        floatingMenuCard(screenSize: screenSize)
                            .position(x: screenSize.width / 2, y: screenSize.height / 2)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.85).combined(with: .opacity),
                                removal: .scale(scale: 0.85).combined(with: .opacity)
                            ))
                    } else {
                        // Floating Circle Button
                        floatingCircleButton
                            .position(currentPosition(screenSize: screenSize))
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        dragOffset = value.translation
                                    }
                                    .onEnded { value in
                                        let finalX = position.x + value.translation.width
                                        let finalY = position.y + value.translation.height
                                        
                                        // Snap to nearest edge (left or right)
                                        let targetX: CGFloat = finalX < screenSize.width / 2 ? 38 : screenSize.width - 38
                                        let clampedY: CGFloat = min(max(finalY, 60), screenSize.height - 70)
                                        
                                        dragOffset = .zero
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                            position = CGPoint(x: targetX, y: clampedY)
                                        }
                                    }
                            )
                            .contextMenu {
                                Button(role: .destructive) {
                                    withAnimation {
                                        floatingMenuEnabled = false
                                        isMenuOpen = false
                                    }
                                } label: {
                                    Label("បិទប៊ូតុងរង្វង់ចេញ (Turn Off Floating Button)", systemImage: "power")
                                }
                            }
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .onAppear {
                updateActiveCount()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("AllPatchesDidRestoreNotification"))) { _ in
                updateActiveCount()
            }
        }
    }

    private func currentPosition(screenSize: CGSize) -> CGPoint {
        let posX = min(max(position.x + dragOffset.width, 28), screenSize.width - 28)
        let posY = min(max(position.y + dragOffset.height, 50), screenSize.height - 50)
        return CGPoint(x: posX, y: posY)
    }
    
    private func updateActiveCount() {
        var count = 0
        for item in patchStore.items {
            if let project = item.project, DevicePatchService.isProjectApplied(projectID: project.id) {
                count += 1
            }
        }
        activeCount = count
    }
    
    // MARK: - Floating Circle Button
    private var floatingCircleButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                isMenuOpen = true
            }
        } label: {
            ZStack {
                // Glass circle background
                Circle()
                    .fill(Color.black.opacity(0.82))
                    .frame(width: 54, height: 54)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [AppTheme.accent, Color.cyan.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2.2
                            )
                    )
                    .shadow(color: AppTheme.accent.opacity(0.45), radius: 8, x: 0, y: 3)
                
                // HackerIcon Logo
                Image("HackerIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .cornerRadius(8)
                    .shadow(color: AppTheme.accent.opacity(0.6), radius: 6)
                
                // Active count badge
                if activeCount > 0 {
                    ZStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 18, height: 18)
                            .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
                            .shadow(color: Color.green.opacity(0.6), radius: 3)
                        
                        Text("\(activeCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .offset(x: 18, y: -18)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Floating MOD Menu")
    }
    
    // MARK: - Floating Menu Card
    private func floatingMenuCard(screenSize: CGSize) -> some View {
        let isLandscape = screenSize.width > screenSize.height
        let cardWidth = min(screenSize.width - 32, isLandscape ? 480 : 350)
        let listMaxHeight = isLandscape ? min(screenSize.height - 130, 220) : 320

        return VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image("HackerIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .cornerRadius(5)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("NH-MOD MENU")
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(.primary)
                    
                    Text("\(activeCount) ACTIVE / \(patchStore.items.count) MODS")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(activeCount > 0 ? Color.green : Color.secondary)
                }
                
                Spacer()
                
                // BUTTON HIDE (HITD)
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        isMenuOpen = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("HIDE")
                            .font(.caption.weight(.bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppTheme.accent.opacity(0.18))
                    .foregroundStyle(AppTheme.accent)
                    .clipShape(Capsule())
                }
                
                // BUTTON X សម្រាប់ CLOSE ផ្ទាំង MENU ឱ្យសល់តែ BUTTON MENU
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        isMenuOpen = false
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(uiColor: .systemGray5))
                            .frame(width: 28, height: 28)
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Menu to Button")

                // BUTTON POWER: បិទប៊ូតុងរង្វង់ចេញទាំងស្រុង
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        floatingMenuEnabled = false
                        isMenuOpen = false
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.15))
                            .frame(width: 28, height: 28)
                        Image(systemName: "power")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.red)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Turn Off Floating Button")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(uiColor: .tertiarySystemBackground).opacity(0.95))
            
            Divider()
            
            // Body - List of installed patches with ON/OFF switches
            ScrollView {
                if patchStore.items.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("គ្មាន MOD ត្រូវបានដំឡើងនៅឡើយទេ")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text("សូមចូលទៅកាន់ Sources ឬ Home ដើម្បី Install MOD ជាមុនសិន")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .padding(.horizontal, 16)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(patchStore.items) { item in
                            FloatingMenuItemRow(
                                item: item,
                                repositoryStore: repositoryStore,
                                onStateChanged: {
                                    updateActiveCount()
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }
            .frame(maxHeight: listMaxHeight)
            
            Divider()
            
            // Footer with Restore All, Turn Off Button, and Bottom HIDE
            HStack(spacing: 12) {
                if activeCount > 0 {
                    Button {
                        _ = try? DevicePatchService.restoreAllAppliedPatches()
                        updateActiveCount()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                            Text("បិទ MOD ទាំងអស់")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                    }
                }

                Button {
                    withAnimation {
                        floatingMenuEnabled = false
                        isMenuOpen = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "power")
                        Text("បិទប៊ូតុងរង្វង់")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        isMenuOpen = false
                    }
                } label: {
                    Text("HIDE MENU")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(uiColor: .tertiarySystemBackground).opacity(0.95))
        }
        .frame(width: cardWidth)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [AppTheme.accent.opacity(0.6), Color.cyan.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .shadow(color: Color.black.opacity(0.35), radius: 20, x: 0, y: 10)
    }
}

// MARK: - Floating Menu Item Row
private struct FloatingMenuItemRow: View {
    let item: PatchLibraryItem
    @ObservedObject var repositoryStore: PackageRepositoryStore
    let onStateChanged: () -> Void
    
    @State private var isApplied: Bool = false
    
    private var matchingPackage: RepositoryPackage? {
        if let originID = item.origin?.packageIdentifier {
            if let match = repositoryStore.packages.first(where: { $0.package.identifier.caseInsensitiveCompare(originID) == .orderedSame }) {
                return match.package
            }
        }
        if let match = repositoryStore.packages.first(where: { repositoryStore.resolvedPackageID(for: $0) == item.id }) {
            return match.package
        }
        guard let name = item.project?.name else { return nil }
        let cleanName = name.replacingOccurrences(of: "_", with: " ").lowercased()
        for record in repositoryStore.packages {
            let pkgName = record.package.name.replacingOccurrences(of: "_", with: " ").lowercased()
            if pkgName == cleanName || cleanName.contains(pkgName) || pkgName.contains(cleanName) {
                return record.package
            }
        }
        return nil
    }
    
    var body: some View {
        HStack(spacing: 10) {
            // Icon
            if let pkg = matchingPackage, pkg.iconURL != nil {
                RepositoryPackageIcon(package: pkg, size: 36)
            } else {
                AppRowIcon(
                    systemName: isApplied ? "checkmark.seal.fill" : "shippingbox.fill",
                    tint: isApplied ? AppTheme.accent : .secondary,
                    symbolSize: 16,
                    frameSize: 36
                )
            }
            
            // Name & Status
            VStack(alignment: .leading, spacing: 2) {
                Text(item.project?.name ?? "Patch")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                
                HStack(spacing: 4) {
                    Text(isApplied ? "ACTIVE" : "OFF")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1)
                        .background(isApplied ? Color.green.opacity(0.2) : Color.secondary.opacity(0.2))
                        .foregroundStyle(isApplied ? Color.green : Color.secondary)
                        .clipShape(Capsule())
                    
                    if let author = item.project?.author, !author.isEmpty {
                        Text(author)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            // Toggle Switch
            if let project = item.project {
                Toggle("", isOn: Binding(
                    get: { isApplied },
                    set: { enabled in
                        _ = try? DevicePatchService.setProjectApplied(project: project, enabled: enabled)
                        isApplied = enabled
                        onStateChanged()
                    }
                ))
                .labelsHidden()
                .tint(AppTheme.accent)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(uiColor: .tertiarySystemBackground).opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            syncState()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("AllPatchesDidRestoreNotification"))) { _ in
            syncState()
        }
    }
    
    private func syncState() {
        if let project = item.project {
            isApplied = DevicePatchService.isProjectApplied(projectID: project.id)
        } else {
            isApplied = false
        }
    }
}

