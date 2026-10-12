import AVFoundation
import UIKit
import UniformTypeIdentifiers
import UserNotifications

final class ShareViewController: UIViewController {
  private let shareStore = ExternalShareStore()
  private let statusStack = UIStackView()
  private let statusTitleLabel = UILabel()
  private let statusMessageLabel = UILabel()
  private let statusActions = UIStackView()
  private let spinner = UIActivityIndicatorView(style: .medium)

  private var originalText = ""
  private var originalURL = ""
  private var normalizedURL = ""
  private var provider = "unknown"
  private var sharedImage: UIImage?
  private var localPreviewTitle = ""
  private var storedRequest: ExternalShareRequest?
  private var didCompleteExtensionRequest = false

  override func viewDidLoad() {
    super.viewDidLoad()
    Self.log(
      "bundleId=\(Bundle.main.bundleIdentifier ?? "unknown") appGroup=\(ExternalShareStore.appGroupIdentifier)"
    )
    configureStatusUI()
    loadSharedItems()
  }

  private func configureStatusUI() {
    view.backgroundColor = .systemBackground

    let closeButton = UIButton(type: .system)
    closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
    closeButton.tintColor = .label
    closeButton.accessibilityLabel = "닫기"
    closeButton.addAction(UIAction { [weak self] _ in self?.closeStatusScreen() }, for: .touchUpInside)

    let brand = UILabel()
    brand.text = "Wefilling"
    brand.font = .systemFont(ofSize: 18, weight: .bold)
    brand.textAlignment = .center

    let headerSpacer = UIView()
    let header = UIStackView(arrangedSubviews: [closeButton, brand, headerSpacer])
    header.axis = .horizontal
    header.alignment = .center
    header.translatesAutoresizingMaskIntoConstraints = false
    closeButton.widthAnchor.constraint(equalToConstant: 52).isActive = true
    headerSpacer.widthAnchor.constraint(equalToConstant: 52).isActive = true
    view.addSubview(header)

    spinner.startAnimating()
    statusTitleLabel.text = "공유 내용을 준비하고 있어요"
    statusTitleLabel.font = .systemFont(ofSize: 19, weight: .bold)
    statusTitleLabel.textAlignment = .center
    statusTitleLabel.numberOfLines = 0
    statusMessageLabel.text = "잠시만 기다려 주세요."
    statusMessageLabel.font = .systemFont(ofSize: 14, weight: .regular)
    statusMessageLabel.textColor = .secondaryLabel
    statusMessageLabel.textAlignment = .center
    statusMessageLabel.numberOfLines = 0
    statusActions.axis = .vertical
    statusActions.spacing = 10

    statusStack.axis = .vertical
    statusStack.alignment = .fill
    statusStack.spacing = 14
    statusStack.translatesAutoresizingMaskIntoConstraints = false
    statusStack.addArrangedSubview(spinner)
    statusStack.addArrangedSubview(statusTitleLabel)
    statusStack.addArrangedSubview(statusMessageLabel)
    statusStack.addArrangedSubview(statusActions)
    view.addSubview(statusStack)

    NSLayoutConstraint.activate([
      header.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
      header.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
      header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
      header.heightAnchor.constraint(equalToConstant: 50),
      statusStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 28),
      statusStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -28),
      statusStack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
    ])
  }

  private func loadSharedItems() {
    let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
    var providers: [NSItemProvider] = []
    for item in items {
      if let attributedText = item.attributedContentText?.string,
         !attributedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        originalText = attributedText
      }
      providers.append(contentsOf: item.attachments ?? [])
    }

    let group = DispatchGroup()
    for itemProvider in providers {
      if itemProvider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
        group.enter()
        itemProvider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, _ in
          let value = (item as? URL)?.absoluteString ?? (item as? NSURL)?.absoluteString ?? ""
          DispatchQueue.main.async {
            if !value.isEmpty { self?.originalURL = value }
            group.leave()
          }
        }
      } else if itemProvider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
        group.enter()
        itemProvider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] item, _ in
          let value = (item as? String) ?? (item as? NSString).map(String.init) ?? ""
          DispatchQueue.main.async {
            if !value.isEmpty { self?.originalText = value }
            group.leave()
          }
        }
      }

      if itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
        group.enter()
        itemProvider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] item, _ in
          let image = self?.image(from: item)
          DispatchQueue.main.async {
            if let image { self?.sharedImage = image }
            group.leave()
          }
        }
      } else if itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
        group.enter()
        itemProvider.loadItem(forTypeIdentifier: UTType.movie.identifier, options: nil) { [weak self] item, _ in
          let url = (item as? URL) ?? (item as? NSURL).map { $0 as URL }
          let image = url.flatMap { self?.videoThumbnail(from: $0) }
          DispatchQueue.main.async {
            if let image { self?.sharedImage = image }
            group.leave()
          }
        }
      }
    }

    group.notify(queue: .main) { [weak self] in self?.persistAndScheduleHandoff() }
  }

  private func persistAndScheduleHandoff() {
    if originalURL.isEmpty {
      originalURL = firstSupportedURL(in: originalText) ?? ""
    }
    normalizedURL = normalize(url: originalURL)
    provider = providerName(for: normalizedURL)
    if provider == "youtube" {
      // YouTube commonly shares its application icon as an attachment. The
      // canonical video thumbnail is the preview; the icon is not post media.
      sharedImage = nil
    }
    localPreviewTitle = originalText
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty && !$0.lowercased().hasPrefix("http") } ?? ""

    let hasPayload = !originalText.trimmingCharacters(
      in: .whitespacesAndNewlines
    ).isEmpty || !originalURL.isEmpty || sharedImage != nil
    guard hasPayload else {
      showStatus(
        title: "공유할 내용을 찾지 못했어요",
        message: "원본 앱으로 돌아가 다시 공유해 주세요.",
        actions: [statusButton(title: "닫기") { [weak self] in self?.cancelExtension() }]
      )
      return
    }

    let id = UUID().uuidString
    let now = Int64(Date().timeIntervalSince1970 * 1_000)
    var imagePath = ""
    if let sharedImage,
       let data = preparedAttachmentData(sharedImage) {
      do {
        imagePath = try shareStore.writeAttachment(data, requestId: id, fileExtension: "jpg")
      } catch {
        if normalizedURL.isEmpty {
          showStorageFailure(code: (error as? ExternalShareStoreError)?.code ?? "share-image-write-failed")
          return
        }
      }
    }

    let preview = makeNativePreview(now: now)
    let request = ExternalShareRequest(
      id: id,
      originalText: originalText,
      draftText: normalizedURL.isEmpty ? originalText : "",
      originalUrl: originalURL,
      normalizedUrl: normalizedURL,
      imagePath: imagePath,
      source: provider,
      receivedAtMillis: now,
      consumed: false,
      previewStatus: normalizedURL.isEmpty ? "unavailable" : "pending",
      preview: preview,
      state: .pending,
      categoryKeys: [defaultCategoryKey()],
      visibility: "public",
      isAnonymous: false,
      visibleToCategoryIds: []
    )
    do {
      try shareStore.savePending(request)
      storedRequest = request
      Self.log("requestId=\(id) pending-save-and-readback=success")
    } catch {
      showStorageFailure(code: (error as? ExternalShareStoreError)?.code ?? "share-save-failed")
      return
    }

    scheduleHandoffNotification(requestId: request.id)
  }

  private func showStatus(title: String, message: String, actions: [UIButton]) {
    spinner.stopAnimating()
    statusTitleLabel.text = title
    statusMessageLabel.text = message
    statusActions.arrangedSubviews.forEach {
      statusActions.removeArrangedSubview($0)
      $0.removeFromSuperview()
    }
    for action in actions { statusActions.addArrangedSubview(action) }
    if actions.isEmpty { spinner.startAnimating() }
    statusStack.isHidden = false
  }

  private func statusButton(
    title: String,
    primary: Bool = false,
    destructive: Bool = false,
    action: @escaping () -> Void
  ) -> UIButton {
    let button = UIButton(type: .system)
    var configuration = primary ? UIButton.Configuration.filled() : UIButton.Configuration.plain()
    configuration.title = title
    configuration.baseBackgroundColor = primary ? .systemBlue : .clear
    configuration.baseForegroundColor = destructive ? .systemRed : (primary ? .white : .label)
    configuration.cornerStyle = .large
    button.configuration = configuration
    button.heightAnchor.constraint(equalToConstant: 48).isActive = true
    button.addAction(UIAction { _ in action() }, for: .touchUpInside)
    return button
  }

  private func showStorageFailure(code: String) {
    Self.log("storage-error-ui code=\(code)")
    showStatus(
      title: "공유 내용을 저장하지 못했어요",
      message: "잠시 후 원본 앱에서 다시 공유해 주세요.",
      actions: [statusButton(title: "닫기") { [weak self] in self?.cancelExtension() }]
    )
  }

  private func closeStatusScreen() {
    guard let request = storedRequest else {
      cancelExtension()
      return
    }
    scheduleHandoffNotification(requestId: request.id)
  }

  private func scheduleHandoffNotification(requestId: String) {
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { [weak self] settings in
      guard let self else { return }
      let canNotify = settings.authorizationStatus == .authorized ||
        settings.authorizationStatus == .provisional ||
        settings.authorizationStatus == .ephemeral
      guard canNotify else {
        Self.log("requestId=\(requestId) handoff-notification=unavailable pending-retained=true")
        self.completeExtensionRequest()
        return
      }
      let content = UNMutableNotificationContent()
      content.title = "Wefilling에서 이어서 작성"
      content.body = "탭하면 공유한 내용으로 포스트 작성 화면이 열립니다."
      content.threadIdentifier = "wefilling-external-share"
      content.userInfo = [
        "type": "external_share",
        "externalShareRequestId": requestId,
      ]
      let request = UNNotificationRequest(
        identifier: "wefilling-external-share-\(requestId)",
        content: content,
        trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
      )
      center.add(request) { [weak self] error in
        Self.log(
          "requestId=\(requestId) handoff-notification=\(error == nil ? "scheduled" : "failed") pending-retained=true"
        )
        self?.completeExtensionRequest()
      }
    }
  }

  private func completeExtensionRequest() {
    DispatchQueue.main.async { [weak self] in
      guard let self, !self.didCompleteExtensionRequest else { return }
      self.didCompleteExtensionRequest = true
      self.extensionContext?.completeRequest(returningItems: nil)
    }
  }

  private func cancelExtension() {
    extensionContext?.cancelRequest(withError: NSError(
      domain: "com.wefilling.app.share",
      code: NSUserCancelledError,
      userInfo: nil
    ))
  }

  private func makeNativePreview(now: Int64) -> ExternalSharePreview? {
    guard !normalizedURL.isEmpty else { return nil }
    let instagram = instagramContent(from: normalizedURL)
    let videoId = youtubeID(from: normalizedURL)
    let thumbnail = videoId.map { "https://i.ytimg.com/vi/\($0)/hqdefault.jpg" } ?? ""
    let title = localPreviewTitle.isEmpty
      ? (provider == "instagram" ? "Instagram에서 공유된 게시물" : "공유된 YouTube 동영상")
      : localPreviewTitle
    return ExternalSharePreview(
      provider: provider,
      originalUrl: originalURL,
      canonicalUrl: normalizedURL,
      contentId: provider == "youtube" ? (videoId ?? "") : (instagram?.shortcode ?? ""),
      shortcode: instagram?.shortcode ?? "",
      contentType: instagram?.contentType ?? "video",
      title: title,
      authorName: "",
      thumbnailUrl: thumbnail,
      aspectRatio: provider == "instagram" ? 1 : 16.0 / 9.0,
      fetchedAtMillis: now,
      previewStatus: provider == "youtube" && !thumbnail.isEmpty ? "ready" : "pending"
    )
  }

  private func defaultCategoryKey() -> String {
    if provider == "youtube" || provider == "instagram" { return "content" }
    if sharedImage != nil { return "photo" }
    return "other"
  }

  private func preparedAttachmentData(_ image: UIImage) -> Data? {
    let longest = max(image.size.width, image.size.height)
    let scale = longest > 1800 ? 1800 / longest : 1
    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: size))
    }
    return rendered.jpegData(compressionQuality: 0.86)
  }

  private func image(from item: NSSecureCoding?) -> UIImage? {
    if let image = item as? UIImage { return image }
    if let data = item as? Data { return UIImage(data: data) }
    guard let url = (item as? URL) ?? (item as? NSURL).map({ $0 as URL }) else { return nil }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    return (try? Data(contentsOf: url)).flatMap(UIImage.init(data:))
  }

  private func videoThumbnail(from url: URL) -> UIImage? {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let asset = AVURLAsset(url: url)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    guard let image = try? generator.copyCGImage(
      at: CMTime(seconds: 0.1, preferredTimescale: 600),
      actualTime: nil
    ) else { return nil }
    return UIImage(cgImage: image)
  }

  private func firstSupportedURL(in text: String) -> String? {
    guard let detector = try? NSDataDetector(
      types: NSTextCheckingResult.CheckingType.link.rawValue
    ) else { return nil }
    let range = NSRange(text.startIndex..., in: text)
    return detector.matches(in: text, range: range)
      .compactMap { $0.url?.absoluteString }
      .first { providerName(for: $0) != "unknown" }
  }

  private func providerName(for value: String) -> String {
    guard let host = URL(string: value)?.host?.lowercased() else { return "unknown" }
    if host == "youtu.be" || host == "youtube.com" ||
       host == "www.youtube.com" || host == "m.youtube.com" {
      return "youtube"
    }
    if host == "instagram.com" || host.hasSuffix(".instagram.com") {
      return "instagram"
    }
    return "unknown"
  }

  private func normalize(url value: String) -> String {
    guard var components = URLComponents(string: value),
          providerName(for: value) != "unknown" else { return "" }
    if providerName(for: value) == "instagram" {
      guard let instagram = instagramContent(from: value) else { return "" }
      return "https://www.instagram.com/\(instagram.route)/\(instagram.shortcode)/"
    }
    components.scheme = "https"
    components.fragment = nil
    return components.url?.absoluteString ?? ""
  }

  private func instagramContent(
    from value: String
  ) -> (shortcode: String, route: String, contentType: String)? {
    guard let url = URL(string: value),
          let host = url.host?.lowercased(),
          host == "instagram.com" || host == "www.instagram.com" else { return nil }
    let segments = url.pathComponents.filter { $0 != "/" }
    guard segments.count == 2,
          segments[0] == "p" || segments[0] == "reel",
          segments[1].range(
            of: "^[A-Za-z0-9_-]{3,100}$",
            options: .regularExpression
          ) != nil else { return nil }
    return (
      shortcode: segments[1],
      route: segments[0],
      contentType: segments[0] == "reel" ? "reel" : "post"
    )
  }

  private func youtubeID(from value: String) -> String? {
    guard let url = URL(string: value), let host = url.host?.lowercased() else { return nil }
    let path = url.pathComponents.filter { $0 != "/" }
    let candidate: String?
    if host == "youtu.be" {
      candidate = path.first
    } else if url.path == "/watch" {
      candidate = URLComponents(url: url, resolvingAgainstBaseURL: false)?
        .queryItems?.first { $0.name == "v" }?.value
    } else if path.first == "shorts" || path.first == "live" {
      candidate = path.count > 1 ? path[1] : nil
    } else {
      candidate = nil
    }
    guard let candidate,
          candidate.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil else {
      return nil
    }
    return candidate
  }

  private static func log(_ message: String) {
    NSLog("[ExternalShare][Extension] %@", message)
  }
}
