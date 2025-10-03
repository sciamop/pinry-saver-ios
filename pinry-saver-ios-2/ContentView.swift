//
//  ContentView.swift
//  PinrySaver
//

import SwiftUI

struct SettingsView: View {
    @State private var pinryBaseURL: String = ""
    @State private var apiToken: String = ""
    @State private var defaultBoardID: String = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Pinry Configuration")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Base URL")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("https://your-pinry-instance.com", text: $pinryBaseURL)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .keyboardType(.URL)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("API Token")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        SecureField("Enter your API token", text: $apiToken)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Default Board ID")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Board ID (optional)", text: $defaultBoardID)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .keyboardType(.numberPad)
                    }
                }
                
                Section {
                    Button(action: saveSettings) {
                        HStack {
                            Spacer()
                            Text("Save Settings")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(8)
                    .disabled(pinryBaseURL.isEmpty || apiToken.isEmpty)
                }
            }
            .navigationTitle("Pinry Settings")
            .onAppear {
                loadSettings()
            }
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
        
        // Load API token from settings
        apiToken = settings.apiToken
        NSLog("SettingsView: Loaded API token from settings, length: \(settings.apiToken.count)")
    }
    
    private func saveSettings() {
        // Validate URL format
        guard URL(string: pinryBaseURL) != nil else {
            showAlert("Please enter a valid URL")
            return
        }
        
        // Save all settings including API token to UserDefaults
        var settings = PinrySettings.shared
        settings.pinryBaseURL = pinryBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.defaultBoardID = defaultBoardID.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.apiToken = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        
        NSLog("SettingsView: Attempting to save API token as plaintext, length: \(settings.apiToken.count)")
        PinrySettings.save(settings)
        NSLog("SettingsView: All settings saved to UserDefaults successfully")
        showAlert("Settings saved successfully!")
    }
    
    private func showAlert(_ message: String) {
        alertMessage = message
        showingAlert = true
    }
}

#Preview {
    SettingsView()
}