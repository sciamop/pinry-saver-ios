import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {
    
    private var uploadTask: Task<Void, Never>?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set up UI
        setupUI()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        handleSharedItems()
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        // Create activity indicator
        let activityIndicator = UIActivityIndicatorView(style: .large)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.startAnimating()
        
        // Create label
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Uploading to Pinry..."
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .headline)
        
        view.addSubview(activityIndicator)
        view.addSubview(label)
        
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
            
            label.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 20),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }
    
    // MARK: - Share Handling
    
    private func handleSharedItems() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            dismissWithError("No shared items found")
            return
        }
        
        let providers = items.flatMap { $0.attachments ?? [] }
        
        uploadTask = Task {
            do {
                let result = try await processSharedItems(providers)
                
                await MainActor.run {
                    if result.success {
                        dismissWithSuccess(result.message)
                    } else {
                        dismissWithError(result.message)
                    }
                }
            } catch {
                await MainActor.run {
                    dismissWithError("Error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func processSharedItems(_ providers: [NSItemProvider]) async throws -> PinryUploadResult {
        var pins: [PinryPin] = []
        
        NSLog("🔍 Processing \(providers.count) providers:")
        for (index, provider) in providers.enumerated() {
            NSLog("  Provider \(index): Types = \(provider.registeredTypeIdentifiers)")
        }
        
        for (index, provider) in providers.enumerated() {
            NSLog("🔍 Processing provider \(index) with types: \(provider.registeredTypeIdentifiers)")
            
            // Check for image first (including JPGs from Safari)
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) ||
               provider.hasItemConformingToTypeIdentifier("public.image") ||
               provider.hasItemConformingToTypeIdentifier("public.jpeg") ||
               provider.hasItemConformingToTypeIdentifier("public.png") {
                NSLog("📷 Found image provider \(index)")
                do {
                    let pin = try await processImageProvider(provider)
                    pins.append(pin)
                    NSLog("✅ Successfully processed image provider \(index)")
                } catch {
                    NSLog("❌ Error processing image provider \(index): \(error)")
                }
            }
            // Then check for URL/text content
            else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                NSLog("🔗 Found URL provider \(index)")
                do {
                    let pin = try await processURLProvider(provider)
                    pins.append(pin)
                    NSLog("✅ Successfully processed URL provider \(index)")
                } catch {
                    NSLog("❌ Error processing URL provider \(index): \(error)")
                }
            }
            // Only try text processing if no URL identifier is found (avoid conflicts)
            else if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) &&
                    !provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                NSLog("📝 Found text provider \(index)")
                do {
                    let pin = try await processURLProvider(provider)
                    pins.append(pin)
                    NSLog("✅ Successfully processed text provider \(index)")
                } catch {
                    NSLog("❌ Error processing text provider \(index): \(error)")
                }
            }
            else {
                NSLog("⚠️ No supported types found for provider \(index): \(provider.registeredTypeIdentifiers)")
            }
        }
        
        guard !pins.isEmpty else {
            return PinryUploadResult(success: false, message: "No supported items found")
        }
        
        // Upload all pins
        let uploader = PinryUploader.shared
        var results: [PinryUploadResult] = []
        
        for pin in pins {
            let result = await uploader.upload(pin)
            results.append(result)
            
            if !result.success {
                return result // Return first failure
            }
        }
        
        if pins.count == 1 {
            return results.first!
        } else {
            let successCount = results.filter { $0.success }.count
            return PinryUploadResult(
                success: true,
                message: "Successfully uploaded \(successCount) out of \(pins.count) pins"
            )
        }
    }
    
    private func processImageProvider(_ provider: NSItemProvider) async throws -> PinryPin {
        NSLog("🔍 Processing image provider. Available types: \(provider.registeredTypeIdentifiers)")
        
        return try await withCheckedThrowingContinuation { continuation in
            // Try different image type identifiers based on what's available
            let imageTypes = [
                UTType.image.identifier,
                "public.image", 
                "public.jpeg",
                "public.png",
                "public.tiff",
                "com.compuserve.gif"
            ]
            
            func tryNextImageType(index: Int) {
                guard index < imageTypes.count else {
                    NSLog("❌ Failed to load image. Provider types: \(provider.registeredTypeIdentifiers)")
                    continuation.resume(throwing: PinryUploadError.networkError(NSError(domain: "PinryShare", code: 1, userInfo: [NSLocalizedDescriptionKey: "No supported image type found"])))
                    return
                }
                
                provider.loadDataRepresentation(forTypeIdentifier: imageTypes[index]) { data, error in
                    if let error = error {
                        NSLog("⚠️ Failed to load \(imageTypes[index]): \(error)")
                        tryNextImageType(index: index + 1)
                    } else if let imageData = data {
                        NSLog("✅ Successfully loaded image: \(imageData.count) bytes using type \(imageTypes[index])")
                        
                        // Generate description from context
                        let description = self.generateImageDescription(from: provider)
                        let source = self.extractSource(from: provider) ?? "iOS Share"
                        
                        let pin = PinryPin(
                            imageData: imageData,
                            description: description,
                            source: source,
                            boardID: ""
                        )
                        
                        continuation.resume(returning: pin)
                    } else {
                        NSLog("⚠️ No data for \(imageTypes[index])")
                        tryNextImageType(index: index + 1)
                    }
                }
            }
            
            tryNextImageType(index: 0)
        }
    }
    
    private func processURLProvider(_ provider: NSItemProvider) async throws -> PinryPin {
        // Simplified URL extraction approach to avoid EXSinkLoadOperator errors
        
        // First, try the most reliable method - suggestedName often contains the URL
        if let title = provider.suggestedName, !title.isEmpty {
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Check if the title is a direct URL
            if trimmedTitle.hasPrefix("http://") || trimmedTitle.hasPrefix("https://") {
                if let url = URL(string: trimmedTitle) {
                    let description = generateURLDescription(from: url)
                    let source = url.host ?? url.absoluteString
                    
                    return PinryPin(
                        url: url,
                        description: description,
                        source: source,
                        boardID: ""
                    )
                }
            }
        }
        
        // If no suggestedName URL, try to load as URL type (correct type for Safari sharing)
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { (obj, error) in
                guard error == nil else {
                    continuation.resume(throwing: PinryUploadError.networkError(error!))
                    return
                }
                
                // Handle both URL objects and string representations
                var finalURL: URL? = nil
                
                if let url = obj as? URL {
                    finalURL = url
                } else if let string = obj as? String {
                    let trimmedString = string.trimmingCharacters(in: .whitespacesAndNewlines)
                    finalURL = URL(string: trimmedString)
                }
                
                guard let url = finalURL else {
                    continuation.resume(throwing: PinryUploadError.networkError(NSError(domain: "PinryShare", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not parse URL from share data"])))
                    return
                }
                
                // Create pin with URL - Pinry will fetch the image!
                let description = self.generateURLDescription(from: url)
                let source = url.host ?? url.absoluteString
                
                let pin = PinryPin(
                    url: url,
                    description: description,
                    source: source,
                    boardID: ""
                )
                
                NSLog("✅ Created URL pin for: \(url)")
                continuation.resume(returning: pin)
            }
        }
    }
    
    private func downloadImageFromURL(_ url: URL) async throws -> Data {
        // This is a simplified implementation - in a real app you might want
        // to extract OG images from meta tags or use a web extraction service
        let (_, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PinryUploadError.networkError(NSError(domain: "PinryShare", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch URL"]))
        }
        
        // For now, create a simple placeholder image
        // In a real implementation, you'd parse the webpage and extract images
        return createPlaceholderImageData(for: url)
    }
    
    private func createPlaceholderImageData(for url: URL) -> Data {
        let size = CGSize(width: 400, height: 300)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            
            let text = url.host ?? "URL"
            let textSize = text.size(withAttributes: attributes)
            let rect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            
            text.draw(in: rect, withAttributes: attributes)
        }
        
        return image.jpegData(compressionQuality: 0.8) ?? Data()
    }
    
    // MARK: - Description Generation
    
    private func generateImageDescription(from provider: NSItemProvider) -> String {
        // Try to get title or other metadata
        if let title = provider.suggestedName {
            return "Image: \(title)"
        }
        
        return "Shared image from iOS"
    }
    
    private func generateURLDescription(from url: URL) -> String {
        var components: [String] = []
        
        if let host = url.host {
            components.append("Link from \(host)")
        }
        
        let title = url.lastPathComponent
        if !title.isEmpty && title != "/" {
            let decodedTitle = title.removingPercentEncoding ?? title
            if decodedTitle.count > 3 && decodedTitle != url.pathExtension {
                components.append(decodedTitle)
            }
        }
        
        return components.isEmpty ? "Shared link" : components.joined(separator: " - ")
    }
    
    private func extractSource(from provider: NSItemProvider) -> String? {
        // Try to extract source app or URL from metadata
        return provider.suggestedName ?? "iOS Share"
    }
    
    // MARK: - Dismissal
    
    private func dismissWithSuccess(_ message: String) {
        showAlert(message: message, isError: false) {
            self.complete()
        }
    }
    
    private func dismissWithError(_ message: String) {
        showAlert(message: message, isError: true) {
            self.cancel(message)
        }
    }
    
    private func showAlert(message: String, isError: Bool, completion: @escaping () -> Void) {
        let alert = UIAlertController(
            title: isError ? "Error" : "Success",
            message: message,
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completion()
        })
        
        present(alert, animated: true)
    }
    
    private func complete() {
        uploadTask?.cancel()
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
    
    private func cancel(_ reason: String) {
        uploadTask?.cancel()
        let error = NSError(domain: "PinryShare", code: 1, userInfo: [NSLocalizedDescriptionKey: reason])
        extensionContext?.cancelRequest(withError: error)
    }
}