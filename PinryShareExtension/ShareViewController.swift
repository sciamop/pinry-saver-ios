import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {
    
    private var uploadTask: Task<Void, Never>?
    private var sharedImageData: Data?
    private var thumbnailImageView: UIImageView?
    private var statusLabel: UILabel?
    private var messageLabel: UILabel?
    private var activityIndicator: UIActivityIndicatorView?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        PinrySettings.invalidateCache()
        
        DispatchQueue.global(qos: .userInitiated).async {
            _ = PinrySettings.load()
        }
        
        DispatchQueue.main.async {
            self.extractImageDataAndStart()
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Items are already being handled from viewDidLoad
    }
    
    // MARK: - Image Extraction
    
    private func extractImageDataAndStart() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            setupUI()
            updateUIForError("No shared items found")
            return
        }
        
        let providers = items.flatMap { $0.attachments ?? [] }
        
        for provider in providers {
            // Check for direct image first
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) ||
               provider.hasItemConformingToTypeIdentifier("public.image") ||
               provider.hasItemConformingToTypeIdentifier("public.jpeg") ||
               provider.hasItemConformingToTypeIdentifier("public.png") {
                loadImageDataForThumbnail(from: provider)
                return
            }
            
            // Check for URL - might be a direct image URL
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                loadURLAndCheckForImage(from: provider)
                return
            }
        }
        
        // No image or URL found
        setupUI()
        handleSharedItems()
    }
    
    private func loadImageDataForThumbnail(from provider: NSItemProvider) {
        let typeToUse = provider.registeredTypeIdentifiers.first(where: { identifier in
            identifier.contains("image") || identifier.contains("jpeg") || identifier.contains("png")
        }) ?? UTType.image.identifier
        
        provider.loadDataRepresentation(forTypeIdentifier: typeToUse) { [weak self] data, error in
            DispatchQueue.main.async {
                if let imageData = data, let image = UIImage(data: imageData) {
                    self?.sharedImageData = imageData
                    self?.setupUI()
                    self?.updateThumbnail(with: image)
                } else {
                    self?.setupUI()
                }
                self?.handleSharedItems()
            }
        }
    }
    
    private func loadURLAndCheckForImage(from provider: NSItemProvider) {
        provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] obj, error in
            var finalURL: URL? = nil
            if let url = obj as? URL {
                finalURL = url
            } else if let string = obj as? String {
                finalURL = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            
            guard let url = finalURL else {
                DispatchQueue.main.async {
                    self?.setupUI()
                    self?.handleSharedItems()
                }
                return
            }
            
            // Check if it's a direct image URL
            let path = url.path.lowercased()
            let isDirectImage = path.hasSuffix(".jpg") || path.hasSuffix(".jpeg") || 
                               path.hasSuffix(".png") || path.hasSuffix(".gif") || 
                               path.hasSuffix(".webp") || path.hasSuffix(".heic")
            
            if isDirectImage {
                self?.downloadImageForThumbnail(from: url)
            } else {
                DispatchQueue.main.async {
                    self?.setupUI()
                    self?.handleSharedItems()
                }
            }
        }
    }
    
    private func downloadImageForThumbnail(from url: URL) {
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200,
                      let image = UIImage(data: data) else {
                    await MainActor.run {
                        self.setupUI()
                        self.handleSharedItems()
                    }
                    return
                }
                
                await MainActor.run {
                    self.sharedImageData = data
                    self.setupUI()
                    self.updateThumbnail(with: image)
                    self.handleSharedItems()
                }
            } catch {
                await MainActor.run {
                    self.setupUI()
                    self.handleSharedItems()
                }
            }
        }
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        // Stack view for all content (no nested cards - just centered stack)
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 24
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        // Always create thumbnail placeholder/container
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 16
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        // If we have image data, use it; otherwise show Pinry icon placeholder
        if let imageData = sharedImageData, let image = UIImage(data: imageData) {
            imageView.image = image
            imageView.backgroundColor = .clear
            imageView.layer.borderWidth = 0
        } else {
            imageView.backgroundColor = .secondarySystemBackground
            imageView.layer.borderWidth = 0
            
            // Show Pinry P icon for URL/non-image shares
            if let pinryIcon = UIImage(named: "PinryIcon") {
                imageView.image = pinryIcon
                imageView.contentMode = .scaleAspectFit
            } else {
                let iconConfig = UIImage.SymbolConfiguration(pointSize: 60, weight: .regular)
                let fallbackImage = UIImage(systemName: "link.circle", withConfiguration: iconConfig)
                imageView.image = fallbackImage
                imageView.tintColor = UIColor(red: 1.0, green: 0.26, blue: 1.0, alpha: 1.0)
            }
            imageView.contentMode = .center
        }
        
        stackView.addArrangedSubview(imageView)
        thumbnailImageView = imageView
        
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 200),
            imageView.heightAnchor.constraint(equalToConstant: 200)
        ])
        
        // Activity indicator
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.color = UIColor(red: 1.0, green: 0.26, blue: 1.0, alpha: 1.0)
        spinner.startAnimating()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(spinner)
        activityIndicator = spinner
        
        // Status label (initially empty, will show checkmark/X on completion)
        let status = UILabel()
        status.text = ""
        status.font = .systemFont(ofSize: 56, weight: .regular)
        status.textAlignment = .center
        status.alpha = 0 // Hidden initially
        stackView.addArrangedSubview(status)
        statusLabel = status
        
        // Message label
        let message = UILabel()
        message.text = "Uploading to Pinry..."
        message.font = .systemFont(ofSize: 17, weight: .semibold)
        message.textColor = .label
        message.textAlignment = .center
        message.numberOfLines = 0
        stackView.addArrangedSubview(message)
        messageLabel = message
        
        view.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 40),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -40)
        ])
        
        // Animate in
        stackView.alpha = 0
        stackView.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5) {
            stackView.alpha = 1
            stackView.transform = .identity
        }
    }
    
    // MARK: - Share Handling
    
    private func handleSharedItems() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            updateUIForError("No shared items found")
            return
        }
        
        let providers = items.flatMap { $0.attachments ?? [] }
        
        uploadTask = Task {
            do {
                let result = try await processSharedItems(providers)
                
                await MainActor.run {
                    if result.success {
                        self.updateUIForSuccess(result.message)
                    } else {
                        self.updateUIForError(result.message)
                    }
                }
            } catch {
                await MainActor.run {
                    self.updateUIForError("Error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func processSharedItems(_ providers: [NSItemProvider]) async throws -> PinryUploadResult {
        var pins: [PinryPin] = []
        
        for provider in providers {
            // Check for image first
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) ||
               provider.hasItemConformingToTypeIdentifier("public.image") ||
               provider.hasItemConformingToTypeIdentifier("public.jpeg") ||
               provider.hasItemConformingToTypeIdentifier("public.png") {
                do {
                    let pin = try await processImageProvider(provider)
                    pins.append(pin)
                } catch {
                    // Silently continue on error
                }
            }
            // Then check for URL/text content
            else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                do {
                    let pin = try await processURLProvider(provider)
                    pins.append(pin)
                } catch {
                    // Silently continue on error
                }
            }
            // Only try text processing if no URL identifier is found
            else if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) &&
                    !provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                do {
                    let pin = try await processURLProvider(provider)
                    pins.append(pin)
                } catch {
                    // Silently continue on error
                }
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
        // Extract metadata before async operations to avoid Sendable issues
        let description = generateImageDescription(from: provider)
        let source = extractSource(from: provider) ?? "iOS Share"
        
        // Reuse already-loaded image data if available
        if let existingData = sharedImageData {
            // Classify the image to get tags
            let tags = await ImageClassifier.shared.classifyImage(existingData)
            
            return PinryPin(
                imageData: existingData,
                description: description,
                source: source,
                boardID: "",
                tags: tags
            )
        }
        
        // Otherwise load it fresh
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
                    continuation.resume(throwing: PinryUploadError.networkError(NSError(domain: "PinryShare", code: 1, userInfo: [NSLocalizedDescriptionKey: "No supported image type found"])))
                    return
                }
                
                provider.loadDataRepresentation(forTypeIdentifier: imageTypes[index]) { [weak self] data, error in
                    if let error = error {
                        tryNextImageType(index: index + 1)
                    } else if let imageData = data {
                        // Store for reuse and update thumbnail if not already set
                        if self?.sharedImageData == nil {
                            self?.sharedImageData = imageData
                            
                            // Update thumbnail on main thread
                            if let image = UIImage(data: imageData) {
                                DispatchQueue.main.async {
                                    self?.updateThumbnail(with: image)
                                }
                            }
                        }
                        
                        // Classify image to get tags
                        Task {
                            let tags = await ImageClassifier.shared.classifyImage(imageData)
                            
                            // Use pre-extracted description and source
                            let pin = PinryPin(
                                imageData: imageData,
                                description: description,
                                source: source,
                                boardID: "",
                                tags: tags
                            )
                            
                            continuation.resume(returning: pin)
                        }
                    } else {
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
                    
                    // Classify image if we have it loaded for thumbnail
                    let tags = await classifySharedImageIfAvailable()
                    
                    return PinryPin(
                        url: url,
                        description: description,
                        source: source,
                        boardID: "",
                        tags: tags
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
                
                // Classify image if we have it loaded for thumbnail
                Task {
                    let tags = await self.classifySharedImageIfAvailable()
                    
                    let pin = PinryPin(
                        url: url,
                        description: description,
                        source: source,
                        boardID: "",
                        tags: tags
                    )
                    
                    continuation.resume(returning: pin)
                }
            }
        }
    }
    
    private func classifySharedImageIfAvailable() async -> [String] {
        guard let imageData = sharedImageData else {
            return []
        }
        return await ImageClassifier.shared.classifyImage(imageData)
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
    
    // MARK: - UI Updates
    
    private func updateThumbnail(with image: UIImage) {
        guard let imageView = thumbnailImageView else {
            return
        }
        
        UIView.transition(with: imageView, duration: 0.3, options: .transitionCrossDissolve) {
            imageView.image = image
            imageView.contentMode = .scaleAspectFill
            imageView.backgroundColor = .clear
            imageView.layer.borderWidth = 0
        }
    }
    
    private func updateUIForSuccess(_ message: String) {
        // Hide spinner
        activityIndicator?.stopAnimating()
        activityIndicator?.alpha = 0
        
        // Show success icon
        statusLabel?.text = "✓"
        statusLabel?.textColor = UIColor(red: 1.0, green: 0.26, blue: 1.0, alpha: 1.0)
        
        // Update message
        messageLabel?.text = message
        
        // Animate changes
        UIView.animate(withDuration: 0.2) {
            self.statusLabel?.alpha = 1
        }
        
        // Bounce the thumbnail
        if let thumbnail = thumbnailImageView {
            bounceView(thumbnail)
        }
        
        // Auto-dismiss after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.complete()
        }
    }
    
    private func updateUIForError(_ message: String) {
        // Hide spinner
        activityIndicator?.stopAnimating()
        activityIndicator?.alpha = 0
        
        // Show error icon
        statusLabel?.text = "❌"
        statusLabel?.textColor = .systemRed
        
        // Update message
        messageLabel?.text = message
        
        // Animate changes
        UIView.animate(withDuration: 0.2) {
            self.statusLabel?.alpha = 1
        }
        
        // Bounce the thumbnail
        if let thumbnail = thumbnailImageView {
            bounceView(thumbnail)
        }
        
        // Auto-dismiss after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.cancel(message)
        }
    }
    
    private func bounceView(_ view: UIView) {
        let animation = CAKeyframeAnimation(keyPath: "transform.scale")
        animation.values = [1.0, 1.2, 0.9, 1.1, 1.0]
        animation.keyTimes = [0, 0.2, 0.4, 0.6, 0.8]
        animation.duration = 0.5
        view.layer.add(animation, forKey: "bounce")
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