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
        hasCredentials = !settings.pinryBaseURL.isEmpty && !settings.apiToken.isEmpty
    }
}

// MARK: - Image Gallery View
struct ImageGalleryView: View {
    @Binding var showingSettings: Bool
    @State private var pins: [PinryPinDetail] = []
    @State private var isLoading = false
    @State private var hasMore = true
    @State private var errorMessage: String?
    
    // Columns for adaptive grid
    let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 250), spacing: 12)
    ]
    
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        // Top anchor for scroll to top
                        Color.clear
                            .frame(height: 0)
                            .id("top")
                        
                        ForEach(pins) { pin in
                            PinThumbnailView(pin: pin)
                                .onAppear {
                                    // Load more when near the end
                                    if pin.id == pins.last?.id && hasMore && !isLoading {
                                        loadMorePins()
                                    }
                                }
                        }
                        
                        // Loading indicator
                        if isLoading {
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
                    .padding(.horizontal, 12)
                    .padding(.top, 60)
                    .padding(.bottom, 20)
                }
                
                // Floating UI elements
                VStack {
                    HStack {
                        // Pinry Logo (upper left) - scroll to top
                        Button(action: {
                            withAnimation {
                                scrollProxy.scrollTo("top", anchor: .top)
                            }
                        }) {
                            PinryLogo()
                                .frame(width: 44, height: 44)
                                .background(Color(uiColor: .systemBackground))
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                        }
                        .padding(.leading, 16)
                        .padding(.top, 16)
                        
                        Spacer()
                        
                        // Gear icon (upper right) - show settings
                        Button(action: {
                            showingSettings = true
                        }) {
                            Image(systemName: "gear")
                                .font(.system(size: 20))
                                .foregroundColor(.primary)
                                .frame(width: 44, height: 44)
                                .background(Color(uiColor: .systemBackground))
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                        }
                        .padding(.trailing, 16)
                        .padding(.top, 16)
                    }
                    
                    Spacer()
                }
            }
        }
        .onAppear {
            if pins.isEmpty {
                loadPins()
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
}

// MARK: - Pin Thumbnail View
struct PinThumbnailView: View {
    let pin: PinryPinDetail
    
    var body: some View {
        Group {
            if let imageUrl = pin.image.bestImageUrl, let url = URL(string: imageUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .aspectRatio(aspectRatio, contentMode: .fit)
                            .overlay(
                                ProgressView()
                            )
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(minWidth: 0, maxWidth: .infinity)
                            .clipped()
                    case .failure:
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .aspectRatio(1.0, contentMode: .fit)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(.gray)
                            )
                    @unknown default:
                        EmptyView()
                    }
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
    
    private var aspectRatio: CGFloat {
        if let width = pin.image.thumbnail?.width,
           let height = pin.image.thumbnail?.height,
           height > 0 {
            return CGFloat(width) / CGFloat(height)
        }
        return 1.0
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
    
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            
            ScrollView {
                HStack {
                    Spacer()
                    
                    VStack(alignment: .leading, spacing: 0) {
                        // Close button for sheet mode
                        if isPresented {
                            HStack {
                                Spacer()
                                Button(action: {
                                    isPresented = false
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 28))
                                        .foregroundColor(Color(uiColor: .secondaryLabel))
                                }
                            }
                            .padding(.top, 16)
                            .padding(.bottom, 8)
                        }
                        
                        // Logo at top
                        HStack {
                            Spacer()
                            PinryLogo()
                                .frame(width: 80, height: 80)
                            Spacer()
                        }
                        .padding(.top, isPresented ? 8 : 60)
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
                            
                            // API Key
                            CustomInputField(
                                label: "API Key:",
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
                            Text("Save Settings")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(
                                    pinryBaseURL.isEmpty || apiToken.isEmpty 
                                        ? Color.gray.opacity(0.3)
                                        : Color.pinryMagenta
                                )
                                .cornerRadius(28)
                        }
                        .disabled(pinryBaseURL.isEmpty || apiToken.isEmpty)
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
    }
    
    private func saveSettings() {
        // Validate URL format
        guard URL(string: pinryBaseURL) != nil else {
            showAlert("Please enter a valid URL")
            return
        }
        
        var settings = PinrySettings.shared
        settings.pinryBaseURL = pinryBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.defaultBoardID = defaultBoardID.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.apiToken = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        
        PinrySettings.save(settings)
        PinrySettings.invalidateCache()
        showAlert("Settings saved successfully!")
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