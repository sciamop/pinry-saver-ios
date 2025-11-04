//
//  ContentView.swift
//  PinrySaver
//

import SwiftUI

// Custom color extension for Pinry magenta
extension Color {
    static let pinryMagenta = Color(red: 1.0, green: 0.26, blue: 1.0) // #FF42FF
}

struct SettingsView: View {
    @State private var pinryBaseURL: String = ""
    @State private var apiToken: String = ""
    @State private var defaultBoardID: String = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 0) {
                    // Logo at top
                    PinryLogo()
                        .frame(width: 80, height: 80)
                        .padding(.top, 60)
                        .padding(.bottom, 40)
                    
                    // Input fields container
                    VStack(spacing: 24) {
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
                    .padding(.horizontal, 40)
                    
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
                    .padding(.horizontal, 40)
                    .padding(.top, 32)
                    
                    Spacer(minLength: 20)
                    
                    // GitHub link at bottom
                    Divider()
                        .padding(.horizontal, 40)
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
        }
        .onAppear {
            loadSettings()
        }
        .alert("Settings", isPresented: $showingAlert) {
            Button("OK") { }
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
    SettingsView()
}