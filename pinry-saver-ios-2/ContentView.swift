//
//  ContentView.swift
//  PinrySaver
//

import SwiftUI

// Custom color extension for Pinry magenta
extension Color {
    static let pinryMagenta = Color(red: 1.0, green: 0.26, blue: 1.0) // #FF42FF
}

// MARK: - Main ContentView
struct ContentView: View {
    @State private var hasCredentials = false
    @State private var showingSettings = false
    
    var body: some View {
        Group {
            if hasCredentials {
                ImageGalleryView(showingSettings: $showingSettings)
                    .sheet(isPresented: $showingSettings) {
                        SettingsView(isPresented: $showingSettings)
                    }
            } else {
                SettingsView(isPresented: .constant(false))
            }
        }
        .onAppear {
            checkCredentials()
        }
        .onChange(of: showingSettings) { oldValue, newValue in
            if !newValue {
                // Settings sheet was dismissed, check credentials again
                checkCredentials()
            }
        }
    }
    
    private func checkCredentials() {
        let settings = PinrySettings.load()
        // Only require URL - API token is optional for reading public pins
        hasCredentials = !settings.pinryBaseURL.isEmpty
    }
}

// MARK: - Image Gallery View
struct ImageGalleryView: View {
    @Binding var showingSettings: Bool
    @State private var pins: [PinryPinDetail] = []
    @State private var isLoading = false
    @State private var hasMore = true
    @State private var errorMessage: String?
    @State private var scrollToTop = false
    @State private var selectedPinIndex: Int? = nil
    @State private var thumbnailCache: [Int: Image] = [:]
    @State private var showGallery = false
    
    var body: some View {
        ZStack(alignment: .top) {
            // Full screen scroll view (always rendering, but may be hidden)
            ScrollViewReader { scrollProxy in
                GeometryReader { geometry in
                    let isLandscape = geometry.size.width > geometry.size.height
                    let columns = isLandscape ? 6 : 3
                    
                    ScrollView {
                        VStack(spacing: 0) {
                            // Top anchor for scroll to top
                            Color.clear
                                .frame(height: 0)
                                .id("top")
                            
                            // Spacer for floating buttons
                            Color.clear
                                .frame(height: 60)
                            
                            // Masonry Grid - responsive to orientation
                            MasonryGrid(pins: pins, spacing: 12, columns: columns) { index, pin in
                                PinThumbnailView(
                                    pin: pin,
                                    isSelected: false,
                                        onImageLoaded: { image in
                                            thumbnailCache[pin.id] = image
                                        }
                                )
                                .onTapGesture {
                                    selectedPinIndex = index
                                }
                                .onAppear {
                                    // Load more when near the end
                                    if pin.id == pins.last?.id && hasMore && !isLoading {
                                        loadMorePins()
                                    }
                                    // Check for new pins when scrolling back to top
                                    if index == 0 && !isLoading {
                                        checkForNewPins()
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                        
                            // Loading indicator for pagination
                            if isLoading && !pins.isEmpty {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            }
                            
                            // Error message
                            if let error = errorMessage {
                                Text(error)
                                    .foregroundColor(.red)
                                    .font(.system(size: 14))
                                    .padding()
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.bottom, 20)
                    }
                    .refreshable {
                        await refreshPins()
                    }
                    .ignoresSafeArea()
                    .onChange(of: scrollToTop) { _, _ in
                        withAnimation {
                            scrollProxy.scrollTo("top", anchor: .top)
                        }
                    }
                }
            }
            .opacity(showGallery ? 1 : 0)
            .animation(.easeInOut(duration: 0.3), value: showGallery)
            
            // Show custom loading screen - fades out when gallery appears
            PinryLoadingView()
                .opacity(showGallery ? 0 : 1)
                .animation(.easeInOut(duration: 0.3), value: showGallery)
                .allowsHitTesting(!showGallery)
                .zIndex(10)
            
            // Floating UI elements - fixed at top of screen
            HStack {
                // Pinry Logo (upper left) - scroll to top - no background
                Button(action: {
                    scrollToTop.toggle()
                }) {
                    PinryLogo()
                        .frame(width: 44, height: 44)
                        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 2)
                }
                
                Spacer()
                
                // Gear icon (upper right) - show settings
                Button(action: {
                    showingSettings = true
                }) {
                    Image(systemName: "gear")
                        .font(.system(size: 20))
                        .foregroundColor(.primary)
                        .padding(2)
                        .background(Color(uiColor: .systemBackground).opacity(0.95))
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            
            // Fullscreen image viewer
            if let index = selectedPinIndex, index < pins.count {
                FullscreenImageViewer(
                    allPins: pins,
                    currentIndex: index,
                    thumbnailCache: thumbnailCache,
                    isPresented: Binding(
                        get: { selectedPinIndex != nil },
                        set: { if !$0 { selectedPinIndex = nil } }
                    ),
                    onNearEnd: {
                        // Load more pins when swiping near the end in fullscreen
                        if hasMore && !isLoading {
                            loadMorePins()
                        }
                    }
                )
            }
        }
        .onAppear {
            if pins.isEmpty {
                loadPins()
                
                // Show gallery after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showGallery = true
                    }
                }
            }
        }
    }
    
    private func loadPins() {
        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            let result = await PinryFetcher.shared.fetchPins(offset: 0, limit: 20)
            
            await MainActor.run {
                isLoading = false
                
                if result.success {
                    pins = result.pins
                    hasMore = result.hasMore
                } else {
                    errorMessage = result.error
                }
            }
        }
    }
    
    private func loadMorePins() {
        guard !isLoading && hasMore else { return }
        
        isLoading = true
        
        Task {
            let result = await PinryFetcher.shared.fetchPins(offset: pins.count, limit: 20)
            
            await MainActor.run {
                isLoading = false
                
                if result.success {
                    pins.append(contentsOf: result.pins)
                    hasMore = result.hasMore
                } else {
                    errorMessage = result.error
                }
            }
        }
    }
    
    private func refreshPins() async {
        // Reload all currently loaded pins (or at least 20)
        let currentCount = max(pins.count, 20)
        let result = await PinryFetcher.shared.fetchPins(offset: 0, limit: currentCount)
        
        if result.success {
            pins = result.pins
            thumbnailCache.removeAll()
            hasMore = result.hasMore
            errorMessage = nil
        } else {
            errorMessage = result.error
        }
    }
    
    private func checkForNewPins() {
        guard !pins.isEmpty else { return }
        
        Task {
            // Fetch just the first pin to see if there are new ones
            let result = await PinryFetcher.shared.fetchPins(offset: 0, limit: 1)
            
            await MainActor.run {
                if result.success, let firstNewPin = result.pins.first {
                    // If the first pin from server is different from our first pin, prepend new ones
                    if firstNewPin.id != pins.first?.id {
                        // Fetch all new pins up to our current first pin
                        Task {
                            await loadNewPinsFromTop()
                        }
                    }
                }
            }
        }
    }
    
    private func loadNewPinsFromTop() async {
        guard let currentFirstPinId = pins.first?.id else { return }
        
        // Fetch pins until we find our current first pin
        var offset = 0
        var newPins: [PinryPinDetail] = []
        
        while true {
            let result = await PinryFetcher.shared.fetchPins(offset: offset, limit: 20)
            
            guard result.success else { break }
            
            // Find where our current first pin appears in the results
            if let indexOfCurrentFirst = result.pins.firstIndex(where: { $0.id == currentFirstPinId }) {
                // Add only the new pins before our current first
                newPins.append(contentsOf: result.pins.prefix(indexOfCurrentFirst))
                break
            } else {
                // Haven't found our current first yet, add all these pins
                newPins.append(contentsOf: result.pins)
                offset += 20
                
                // Safety limit: don't fetch more than 100 new pins
                if newPins.count >= 100 {
                    break
                }
            }
        }
        
        // Prepend new pins to the beginning
        if !newPins.isEmpty {
            pins.insert(contentsOf: newPins, at: 0)
        }
    }
}

// MARK: - Pinry Loading View
struct PinryLoadingView: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var yOffset: CGFloat = 0
    let size: CGFloat
    let desaturated: Bool
    let animated: Bool
    
    init(size: CGFloat = 256, desaturated: Bool = false, animated: Bool = true) {
        self.size = size
        self.desaturated = desaturated
        self.animated = animated
    }
    
    var body: some View {
        ZStack {
            if size >= 200 {
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()
            }
            
            VStack {
                Spacer()
                
                // Pinry logo with motion blur
                ZStack {
                    if animated {
                        // Motion blur trail (3 copies instead of 5)
                        ForEach(0..<3, id: \.self) { index in
                            Group {
                                if desaturated {
                                    PinryLogo()
                                        .colorMultiply(colorScheme == .dark ? .white : .black)
                                } else {
                                    PinryLogo()
                                }
                            }
                            .frame(width: size, height: size)
                            .opacity((desaturated ? 0.3 : 1.0) * (1.0 - CGFloat(index) * 0.3))
                            .offset(y: yOffset - CGFloat(index) * 20)
                        }
                    } else {
                        // Static version (no motion blur)
                        Group {
                            if desaturated {
                                PinryLogo()
                                    .colorMultiply(colorScheme == .dark ? .white : .black)
                            } else {
                                PinryLogo()
                            }
                        }
                        .frame(width: size, height: size)
                        .opacity(desaturated ? 0.3 : 1.0)
                    }
                }
                .frame(width: size, height: size, alignment: .top)
                .clipped()
                .drawingGroup() // Render as a single layer for better performance
                
                Spacer()
            }
        }
        .onAppear {
            if animated {
                yOffset = -size
                withAnimation(
                    .easeInOut(duration: 0.5)
                    .repeatForever(autoreverses: false)
                ) {
                    yOffset = size
                }
            }
        }
    }
}


// MARK: - Masonry Grid Layout
struct MasonryGrid<Content: View>: View {
    let pins: [PinryPinDetail]
    let spacing: CGFloat
    let columns: Int
    let content: (Int, PinryPinDetail) -> Content
    
    init(
        pins: [PinryPinDetail],
        spacing: CGFloat = 12,
        columns: Int = 2,
        @ViewBuilder content: @escaping (Int, PinryPinDetail) -> Content
    ) {
        self.pins = pins
        self.spacing = spacing
        self.columns = columns
        self.content = content
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(0..<columns, id: \.self) { columnIndex in
                LazyVStack(spacing: spacing) {
                    ForEach(Array(pins.enumerated()), id: \.element.id) { index, pin in
                        if index % columns == columnIndex {
                            content(index, pin)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Fullscreen Image Viewer
struct FullscreenImageViewer: View {
    let allPins: [PinryPinDetail]
    @State var currentIndex: Int
    let thumbnailCache: [Int: Image]
    @Binding var isPresented: Bool
    let onNearEnd: () -> Void
    
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var showTags = false
    
    var body: some View {
        GeometryReader { geometry in
            let screenHeight = geometry.size.height
            let dragProgress = min(max(dragOffset / screenHeight, 0), 1)
            let dismissThreshold: CGFloat = 0.125
            let scale = 1.0 - (dragProgress * 0.6) // Shrink to 60% at full drag
            let backgroundOpacity = 1.0 - dragProgress
            
            ZStack {
                // Black background fades out as you drag
                Color.black
                    .opacity(backgroundOpacity)
                    .ignoresSafeArea()
                    .onTapGesture {
                        if !isDragging {
                            isPresented = false
                        }
                    }
                
                // Fullscreen viewer with swipe
                TabView(selection: $currentIndex) {
                    ForEach(Array(allPins.enumerated()), id: \.element.id) { index, pinItem in
                        FullSizeImageView(
                            pin: pinItem,
                            cachedThumbnail: thumbnailCache[pinItem.id],
                            showTags: $showTags,
                            onDismissGesture: { translation in
                                // Use shorter dimension for dismiss zone calculation
                                let screenWidth = geometry.size.width
                                let screenHeight = geometry.size.height
                                let shorterDimension = min(screenWidth, screenHeight)
                                
                                // Middle 50% based on shorter dimension, centered
                                let zoneWidth = shorterDimension * 0.5
                                let leftBound = (screenWidth - zoneWidth) / 2
                                let rightBound = (screenWidth + zoneWidth) / 2
                                let startX = translation.startLocation.x
                                let inMiddleZone = startX >= leftBound && startX <= rightBound
                                
                                // Check if this is primarily a vertical drag down
                                let isVerticalDown = translation.translation.height > 0 && 
                                                     abs(translation.translation.height) > abs(translation.translation.width)
                                
                                // Allow dismiss gesture if in middle zone and vertical
                                if isVerticalDown && inMiddleZone {
                                    isDragging = true
                                    dragOffset = translation.translation.height
                                    return true
                                }
                                return false
                            },
                            onDismissEnd: {
                                isDragging = false
                                
                                // Check if we've passed the dismiss threshold
                                if dragProgress >= dismissThreshold {
                                    // Dismiss
                                    withAnimation(.easeOut(duration: 0.25)) {
                                        dragOffset = screenHeight
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                        isPresented = false
                                    }
                                } else {
                                    // Snap back
                                    withAnimation(.interpolatingSpring(stiffness: 300, damping: 25)) {
                                        dragOffset = 0
                                    }
                                }
                            }
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
                .scaleEffect(scale)
                .offset(y: dragOffset)
                
                // Close button
                VStack {
                    HStack {
                        Spacer()
                        Button(action: {
                            if !isDragging {
                                isPresented = false
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.5), radius: 4)
                        }
                        .padding(16)
                    }
                    Spacer()
                }
                .opacity(backgroundOpacity)
            }
        }
        .onChange(of: currentIndex) { _, newIndex in
            // Check if we're within the last 3 images, trigger load more
            if newIndex >= allPins.count - 3 {
                onNearEnd()
            }
        }
    }
}

// MARK: - Full Size Image View
struct FullSizeImageView: View {
    let pin: PinryPinDetail
    let cachedThumbnail: Image?
    @Binding var showTags: Bool
    let onDismissGesture: ((DragGesture.Value) -> Bool)?
    let onDismissEnd: (() -> Void)?
    @State private var fullSizeImage: Image? = nil
    @State private var isLoadingFull = false
    
    // Zoom state
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    init(pin: PinryPinDetail, cachedThumbnail: Image?, showTags: Binding<Bool>, onDismissGesture: ((DragGesture.Value) -> Bool)? = nil, onDismissEnd: (() -> Void)? = nil) {
        self.pin = pin
        self.cachedThumbnail = cachedThumbnail
        self._showTags = showTags
        self.onDismissGesture = onDismissGesture
        self.onDismissEnd = onDismissEnd
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Main image content
            ZStack {
                // Show cached thumbnail immediately - ZERO delay
                if let thumbnail = cachedThumbnail {
                    thumbnail
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
                
                // Full size image (fades in on top)
                if let fullImg = fullSizeImage {
                    fullImg
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .transition(.opacity)
                }
            }
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
            // Pinch to zoom
            MagnificationGesture()
                .onChanged { value in
                    scale = lastScale * value
                }
                .onEnded { value in
                    lastScale = scale
                    // Limit zoom between 1x and 5x
                    let limitedScale = min(max(scale, 1.0), 5.0)
                    withAnimation(.interpolatingSpring(stiffness: 300, damping: 30)) {
                        scale = limitedScale
                        lastScale = limitedScale
                        
                        // Reset offset if zoomed out completely
                        if scale <= 1.0 {
                            offset = .zero
                            lastOffset = .zero
                        }
                    }
                }
        )
        .simultaneousGesture(
            // Pan when zoomed OR dismiss when not zoomed
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    if scale > 1.0 {
                        // Pan around when zoomed
                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                    } else {
                        // Try dismiss gesture when not zoomed
                        _ = onDismissGesture?(value)
                    }
                }
                .onEnded { value in
                    if scale > 1.0 {
                        lastOffset = offset
                    } else {
                        onDismissEnd?()
                    }
                }
            )
            .onTapGesture(count: 2) {
                // Double-tap to reset zoom
                withAnimation(.interpolatingSpring(stiffness: 300, damping: 30)) {
                    scale = 1.0
                    lastScale = 1.0
                    offset = .zero
                    lastOffset = .zero
                }
            }
            
            // Tag icon and display in upper left
            VStack(alignment: .leading, spacing: 8) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showTags.toggle()
                    }
                }) {
                    let hasTags = pin.tags?.isEmpty == false
                    let iconColor = hasTags ? Color.pinryMagenta : Color.white
                    
                    Image(systemName: showTags ? "tag.fill" : "tag")
                        .font(.system(size: 24))
                        .foregroundColor(iconColor)
                        .padding(12)
                        .background(Color.black.opacity(0.4))
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.3), radius: 4)
                }
                
                // Tags display
                if showTags, let tags = pin.tags, !tags.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(16)
                        }
                    }
                    .padding(.leading, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(16)
        }
        .onAppear {
            // Reset zoom state when image appears
            scale = 1.0
            lastScale = 1.0
            offset = .zero
            lastOffset = .zero
            
            if fullSizeImage == nil && !isLoadingFull {
                loadFullSizeImage()
            }
        }
        .id(pin.id) // Force fresh view for each image
    }
    
    private func loadFullSizeImage() {
        guard let fullUrl = pin.image.fullSizeUrl, let url = URL(string: fullUrl) else { return }
        
        isLoadingFull = true
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            fullSizeImage = Image(uiImage: uiImage)
                        }
                    }
                }
            } catch {
                print("Failed to load full-size image: \(error)")
            }
        }
    }
}

// MARK: - Cached Async Image (doesn't reload)
struct CachedAsyncImage: View {
    let url: String
    @State private var image: Image? = nil
    
    var body: some View {
        Group {
            if let img = image {
                img
                    .resizable()
            } else if let imageUrl = URL(string: url) {
                AsyncImage(url: imageUrl) { phase in
                    if case .success(let loadedImage) = phase {
                        loadedImage
                            .resizable()
                            .onAppear {
                                image = loadedImage
                            }
                    }
                }
            }
        }
    }
}

// MARK: - Pin Thumbnail View
struct PinThumbnailView: View {
    let pin: PinryPinDetail
    let isSelected: Bool
    let onImageLoaded: ((Image) -> Void)?
    @State private var thumbnailImage: Image? = nil
    @State private var isLoading = false
    @State private var loadFailed = false
    @State private var retryCount = 0
    
    init(pin: PinryPinDetail, isSelected: Bool = false, onImageLoaded: ((Image) -> Void)? = nil) {
        self.pin = pin
        self.isSelected = isSelected
        self.onImageLoaded = onImageLoaded
    }
    
    var body: some View {
        Group {
            if let thumbImg = thumbnailImage {
                thumbImg
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if let thumbnailUrl = pin.image.thumbnail?.url {
                // Show loader immediately, then load thumbnail
                ZStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.05))
                        .aspectRatio(thumbnailAspectRatio, contentMode: .fit)
                        .overlay(
                            PinryLoadingView(size: 64, desaturated: true, animated: false)
                                .rotationEffect(.degrees(pin.id % 2 == 0 ? 45 : -45))
                        )
                    
                    if loadFailed && retryCount >= 3 {
                        // Show error after 3 retries
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.red)
                            .font(.system(size: 32))
                    }
                }
                .onAppear {
                    loadThumbnail(url: thumbnailUrl)
                }
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(1.0, contentMode: .fit)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                    )
            }
        }
        .cornerRadius(8)
    }
    
    private var thumbnailAspectRatio: CGFloat {
        if let width = pin.image.thumbnail?.width,
           let height = pin.image.thumbnail?.height,
           height > 0 {
            return CGFloat(width) / CGFloat(height)
        }
        return 1.0
    }
    
    private func loadThumbnail(url: String) {
        guard thumbnailImage == nil && !isLoading else { return }
        guard let imageUrl = URL(string: url) else { return }
        
        isLoading = true
        
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: imageUrl)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                
                if httpResponse.statusCode == 200, let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        let image = Image(uiImage: uiImage)
                        thumbnailImage = image
                        onImageLoaded?(image)
                        isLoading = false
                        loadFailed = false
                    }
                } else {
                    throw URLError(.badServerResponse)
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    loadFailed = true
                    
                    // Retry up to 3 times with exponential backoff
                    if retryCount < 3 {
                        retryCount += 1
                        let delay = Double(retryCount) * 0.5 // 0.5s, 1s, 1.5s
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            loadThumbnail(url: url)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @Binding var isPresented: Bool
    @State private var pinryBaseURL: String = ""
    @State private var apiToken: String = ""
    @State private var defaultBoardID: String = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var isValidating = false
    @State private var validationSuccess = false
    @State private var isFirstTimeUser = false
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            
            ScrollView {
                HStack {
                    Spacer()
                    
                    VStack(alignment: .leading, spacing: 0) {
                        // Logo at top
                        HStack {
                            Spacer()
                            PinryLogo()
                                .frame(width: 80, height: 80)
                            Spacer()
                        }
                        .padding(.top, isPresented ? 60 : 60)
                        .padding(.bottom, 40)
                        
                        // Input fields container
                        VStack(alignment: .leading, spacing: 24) {
                            // Pinry Server URL
                            CustomInputField(
                                label: "Pinry Server URL:",
                                placeholder: "https://pinry.whistlehog.com",
                                text: $pinryBaseURL,
                                isSecure: false,
                                keyboardType: .URL
                            )
                            
                            // API Key (optional)
                            CustomInputField(
                                label: "API Key (optional, required for saving):",
                                placeholder: "",
                                text: $apiToken,
                                isSecure: true
                            )
                            
                            // Default Board ID
                            CustomInputField(
                                label: "Default Board ID (optional):",
                                placeholder: "Leave empty to use default",
                                text: $defaultBoardID,
                                isSecure: false,
                                keyboardType: .numberPad
                            )
                        }
                        
                        // Save Settings Button
                        Button(action: saveSettings) {
                            Text(isFirstTimeUser ? "Save Settings and Show Pinry" : "Save Settings")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(
                                    pinryBaseURL.isEmpty
                                        ? Color.gray.opacity(0.3)
                                        : Color.pinryMagenta
                                )
                                .cornerRadius(28)
                        }
                        .disabled(pinryBaseURL.isEmpty || isValidating)
                        .padding(.top, 32)
                        
                        Spacer(minLength: 20)
                        
                        // GitHub link at bottom
                        VStack {
                            Divider()
                                .padding(.top, 30)
                            
                            Link(destination: URL(string: "https://github.com/pinry/pinry")!) {
                                Text("View on GitHub")
                                    .font(.system(size: 15))
                                    .foregroundColor(Color(uiColor: .secondaryLabel))
                            }
                            .padding(.top, 16)
                            .padding(.bottom, 30)
                        }
                    }
                    .frame(maxWidth: 480)
                    .padding(.horizontal, 32)
                    
                    Spacer()
                }
            }
            
            // Close button - positioned absolutely in top right corner
            if isPresented {
                Button(action: {
                    isPresented = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(Color(uiColor: .secondaryLabel))
                }
                .padding(.top, 16)
                .padding(.trailing, 16)
            }
            
            // Validation interstitial
            if isValidating {
                ZStack {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 24) {
                        if validationSuccess {
                            // Success state
                            Text("✓")
                                .font(.system(size: 60, weight: .regular))
                                .foregroundColor(.pinryMagenta)
                        } else {
                            // Loading state
                            PinryLoadingView(size: 80, desaturated: false, animated: true)
                                .frame(width: 80, height: 80)
                        }
                        
                        Text(validationSuccess ? "Connected!" : "Validating Pinry server...")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    .padding(40)
                    .background(Color(uiColor: .systemBackground))
                    .cornerRadius(20)
                    .shadow(radius: 20)
                }
            }
        }
        .onAppear {
            loadSettings()
        }
        .alert("Settings", isPresented: $showingAlert) {
            Button("OK") {
                if isPresented {
                    isPresented = false
                }
            }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func loadSettings() {
        let settings = PinrySettings.load()
        pinryBaseURL = settings.pinryBaseURL
        defaultBoardID = settings.defaultBoardID
        apiToken = settings.apiToken
        
        // Check if this is a first-time user (no URL configured)
        isFirstTimeUser = settings.pinryBaseURL.isEmpty
    }
    
    private func saveSettings() {
        // Validate URL format
        let trimmedURL = pinryBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard URL(string: trimmedURL) != nil else {
            showAlert("Please enter a valid URL")
            return
        }
        
        // Show validation interstitial
        isValidating = true
        
        Task {
            // Validate the Pinry server
            let trimmedToken = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
            let validation = await PinryFetcher.shared.validatePinryServer(
                baseURL: trimmedURL,
                apiToken: trimmedToken.isEmpty ? nil : trimmedToken
            )
            
            await MainActor.run {
                if validation.isValid {
                    // Save settings
                    var settings = PinrySettings.shared
                    settings.pinryBaseURL = trimmedURL
                    settings.defaultBoardID = defaultBoardID.trimmingCharacters(in: .whitespacesAndNewlines)
                    settings.apiToken = trimmedToken
                    
                    PinrySettings.save(settings)
                    PinrySettings.invalidateCache()
                    
                    // Show success state
                    validationSuccess = true
                    
                    // Wait 1.5 seconds, then dismiss
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
                        await MainActor.run {
                            isValidating = false
                            validationSuccess = false
                            
                            // Dismiss settings to show gallery
                            if isPresented {
                                isPresented = false
                            }
                        }
                    }
                } else {
                    // Show error and keep user in settings
                    isValidating = false
                    validationSuccess = false
                    
                    let errorMsg = validation.errorMessage ?? "Unknown error"
                    showAlert("Unable to connect to Pinry server:\n\n\(errorMsg)")
                }
            }
        }
    }
    
    private func showAlert(_ message: String) {
        alertMessage = message
        showingAlert = true
    }
}

// Custom Input Field Component
struct CustomInputField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let isSecure: Bool
    var keyboardType: UIKeyboardType = .default
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(Color(uiColor: .secondaryLabel))
            
            if isSecure {
                SecureField(placeholder, text: $text)
                    .textFieldStyle(CustomTextFieldStyle())
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            } else {
                TextField(placeholder, text: $text)
                    .textFieldStyle(CustomTextFieldStyle())
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(keyboardType)
            }
        }
    }
}

// Custom TextField Style
struct CustomTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(uiColor: .separator), lineWidth: 1)
            )
            .font(.system(size: 15))
    }
}

// Pinry Logo Component - Uses PNG asset
struct PinryLogo: View {
    var body: some View {
        Image("PinryIcon")
            .resizable()
            .aspectRatio(contentMode: .fit)
    }
}

#Preview {
    ContentView()
}