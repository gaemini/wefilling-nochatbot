import Foundation

enum ExternalShareState: String, Codable {
  case pending
  case extensionClaimed
  case runnerClaimed
  case posted
  case discarded
}

enum ExternalShareClaimOwner {
  case shareExtension
  case runner

  var state: ExternalShareState {
    switch self {
    case .shareExtension: return .extensionClaimed
    case .runner: return .runnerClaimed
    }
  }
}

struct ExternalSharePreview: Codable {
  var provider: String
  var originalUrl: String
  var canonicalUrl: String
  var contentId: String
  var shortcode: String
  var contentType: String
  var title: String
  var authorName: String
  var thumbnailUrl: String
  var aspectRatio: Double
  var fetchedAtMillis: Int64
  var previewStatus: String

  init(
    provider: String = "",
    originalUrl: String = "",
    canonicalUrl: String = "",
    contentId: String = "",
    shortcode: String = "",
    contentType: String = "",
    title: String = "",
    authorName: String = "",
    thumbnailUrl: String = "",
    aspectRatio: Double = 0,
    fetchedAtMillis: Int64 = 0,
    previewStatus: String = "unavailable"
  ) {
    self.provider = provider
    self.originalUrl = originalUrl
    self.canonicalUrl = canonicalUrl
    self.contentId = contentId
    self.shortcode = shortcode
    self.contentType = contentType
    self.title = title
    self.authorName = authorName
    self.thumbnailUrl = thumbnailUrl
    self.aspectRatio = aspectRatio
    self.fetchedAtMillis = fetchedAtMillis
    self.previewStatus = previewStatus
  }

  private enum CodingKeys: String, CodingKey {
    case provider
    case originalUrl
    case canonicalUrl
    case contentId
    case shortcode
    case contentType
    case title
    case authorName
    case thumbnailUrl
    case aspectRatio
    case fetchedAtMillis
    case previewStatus
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    provider = (try? values.decodeIfPresent(String.self, forKey: .provider)) ?? ""
    originalUrl = (try? values.decodeIfPresent(String.self, forKey: .originalUrl)) ?? ""
    canonicalUrl = (try? values.decodeIfPresent(String.self, forKey: .canonicalUrl)) ?? ""
    contentId = (try? values.decodeIfPresent(String.self, forKey: .contentId)) ?? ""
    shortcode = (try? values.decodeIfPresent(String.self, forKey: .shortcode)) ?? ""
    contentType = (try? values.decodeIfPresent(String.self, forKey: .contentType)) ?? ""
    title = (try? values.decodeIfPresent(String.self, forKey: .title)) ?? ""
    authorName = (try? values.decodeIfPresent(String.self, forKey: .authorName)) ?? ""
    thumbnailUrl = (try? values.decodeIfPresent(String.self, forKey: .thumbnailUrl)) ?? ""
    aspectRatio = (try? values.decodeIfPresent(Double.self, forKey: .aspectRatio)) ?? 0
    fetchedAtMillis = (try? values.decodeIfPresent(Int64.self, forKey: .fetchedAtMillis)) ?? 0
    previewStatus = (try? values.decodeIfPresent(String.self, forKey: .previewStatus)) ?? "unavailable"
  }
}

struct ExternalShareRequest: Codable {
  var id: String
  var originalText: String
  var draftText: String
  var originalUrl: String
  var normalizedUrl: String
  var imagePath: String
  var source: String
  var receivedAtMillis: Int64
  var consumed: Bool
  var previewStatus: String
  var preview: ExternalSharePreview?
  var state: ExternalShareState
  var claimedAtMillis: Int64?
  var categoryKeys: [String]
  var visibility: String
  var isAnonymous: Bool
  var visibleToCategoryIds: [String]

  init(
    id: String,
    originalText: String = "",
    draftText: String = "",
    originalUrl: String = "",
    normalizedUrl: String = "",
    imagePath: String = "",
    source: String = "unknown",
    receivedAtMillis: Int64,
    consumed: Bool = false,
    previewStatus: String = "unavailable",
    preview: ExternalSharePreview? = nil,
    state: ExternalShareState = .pending,
    claimedAtMillis: Int64? = nil,
    categoryKeys: [String] = [],
    visibility: String = "public",
    isAnonymous: Bool = false,
    visibleToCategoryIds: [String] = []
  ) {
    self.id = id
    self.originalText = originalText
    self.draftText = draftText
    self.originalUrl = originalUrl
    self.normalizedUrl = normalizedUrl
    self.imagePath = imagePath
    self.source = source
    self.receivedAtMillis = receivedAtMillis
    self.consumed = consumed
    self.previewStatus = previewStatus
    self.preview = preview
    self.state = state
    self.claimedAtMillis = claimedAtMillis
    self.categoryKeys = categoryKeys
    self.visibility = visibility
    self.isAnonymous = isAnonymous
    self.visibleToCategoryIds = visibleToCategoryIds
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case originalText
    case draftText
    case originalUrl
    case normalizedUrl
    case imagePath
    case source
    case receivedAtMillis
    case consumed
    case previewStatus
    case preview
    case state
    case claimedAtMillis
    case categoryKeys
    case visibility
    case isAnonymous
    case visibleToCategoryIds
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = (try? values.decodeIfPresent(String.self, forKey: .id)) ?? ""
    originalText = (try? values.decodeIfPresent(String.self, forKey: .originalText)) ?? ""
    draftText = (try? values.decodeIfPresent(String.self, forKey: .draftText)) ?? ""
    originalUrl = (try? values.decodeIfPresent(String.self, forKey: .originalUrl)) ?? ""
    normalizedUrl = (try? values.decodeIfPresent(String.self, forKey: .normalizedUrl)) ?? ""
    imagePath = (try? values.decodeIfPresent(String.self, forKey: .imagePath)) ?? ""
    source = (try? values.decodeIfPresent(String.self, forKey: .source)) ?? "unknown"
    receivedAtMillis = (try? values.decodeIfPresent(Int64.self, forKey: .receivedAtMillis)) ?? 0
    consumed = (try? values.decodeIfPresent(Bool.self, forKey: .consumed)) ?? false
    previewStatus = (try? values.decodeIfPresent(String.self, forKey: .previewStatus)) ?? "unavailable"
    preview = try? values.decodeIfPresent(ExternalSharePreview.self, forKey: .preview)
    let rawState = (try? values.decodeIfPresent(String.self, forKey: .state)) ?? ""
    switch rawState {
    case ExternalShareState.extensionClaimed.rawValue:
      state = .extensionClaimed
    case ExternalShareState.runnerClaimed.rawValue, "claimed":
      state = .runnerClaimed
    case ExternalShareState.posted.rawValue, "completed":
      state = .posted
    case ExternalShareState.discarded.rawValue:
      state = .discarded
    default:
      state = consumed ? .runnerClaimed : .pending
    }
    claimedAtMillis = try? values.decodeIfPresent(Int64.self, forKey: .claimedAtMillis)
    categoryKeys = (try? values.decodeIfPresent([String].self, forKey: .categoryKeys)) ?? []
    visibility = (try? values.decodeIfPresent(String.self, forKey: .visibility)) ?? "public"
    isAnonymous = (try? values.decodeIfPresent(Bool.self, forKey: .isAnonymous)) ?? false
    visibleToCategoryIds =
      (try? values.decodeIfPresent([String].self, forKey: .visibleToCategoryIds)) ?? []
  }

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(id, forKey: .id)
    try values.encode(originalText, forKey: .originalText)
    try values.encode(draftText, forKey: .draftText)
    try values.encode(originalUrl, forKey: .originalUrl)
    try values.encode(normalizedUrl, forKey: .normalizedUrl)
    try values.encode(imagePath, forKey: .imagePath)
    try values.encode(source, forKey: .source)
    try values.encode(receivedAtMillis, forKey: .receivedAtMillis)
    try values.encode(consumed, forKey: .consumed)
    try values.encode(previewStatus, forKey: .previewStatus)
    if let preview {
      try values.encode(preview, forKey: .preview)
    } else {
      try values.encodeNil(forKey: .preview)
    }
    try values.encode(state, forKey: .state)
    try values.encodeIfPresent(claimedAtMillis, forKey: .claimedAtMillis)
    try values.encode(categoryKeys, forKey: .categoryKeys)
    try values.encode(visibility, forKey: .visibility)
    try values.encode(isAnonymous, forKey: .isAnonymous)
    try values.encode(visibleToCategoryIds, forKey: .visibleToCategoryIds)
  }
}

enum ExternalShareStoreError: Error, LocalizedError {
  case containerUnavailable
  case invalidRequestId
  case jsonEncodingFailed(Error)
  case fileWriteFailed(Error)
  case readBackFailed(Error?)
  case requestNotFound
  case requestAlreadyClaimed
  case invalidOutcome

  var code: String {
    switch self {
    case .containerUnavailable: return "app-group-container-unavailable"
    case .invalidRequestId: return "invalid-share-id"
    case .jsonEncodingFailed: return "share-json-encoding-failed"
    case .fileWriteFailed: return "share-file-write-failed"
    case .readBackFailed: return "share-readback-failed"
    case .requestNotFound: return "share-request-not-found"
    case .requestAlreadyClaimed: return "share-request-already-claimed"
    case .invalidOutcome: return "invalid-share-outcome"
    }
  }

  var errorDescription: String? { code }
}

final class ExternalShareStore {
  static let appGroupIdentifier = "group.com.wefilling.app"
  static let legacyPendingKey = "pending_shares_json"

  private static let rootDirectoryName = "ExternalShares"
  private static let pendingDirectoryName = "pending"
  private static let claimedDirectoryName = "claimed"
  private static let attachmentDirectoryName = "attachments"
  private static let corruptDirectoryName = "corrupt"
  private static let requestLifetimeMillis: Int64 = 7 * 24 * 60 * 60 * 1_000
  private static let claimRecoveryMillis: Int64 = 30 * 60 * 1_000

  private let fileManager: FileManager
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
    encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    decoder = JSONDecoder()
  }

  func savePending(_ request: ExternalShareRequest) throws {
    try validateRequestId(request.id)
    var pending = request
    pending.state = .pending
    pending.consumed = false
    pending.claimedAtMillis = nil
    let target = try requestURL(id: pending.id, directory: Self.pendingDirectoryName)
    try writeAndVerify(pending, to: target)
    Self.log("requestId=\(pending.id) provider=\(pending.source) normalizedUrl=\(!pending.normalizedUrl.isEmpty) pending-write=success")
  }

  func writeAttachment(
    _ data: Data,
    requestId: String,
    fileExtension: String = "jpg"
  ) throws -> String {
    try validateRequestId(requestId)
    let safeExtension = fileExtension.range(
      of: "^[A-Za-z0-9]{1,8}$",
      options: .regularExpression
    ) == nil ? "bin" : fileExtension.lowercased()
    let directory = try directoryURL(Self.attachmentDirectoryName)
    let target = directory.appendingPathComponent("\(requestId).\(safeExtension)")
    do {
      try data.write(to: target, options: .atomic)
      let readBack = try Data(contentsOf: target)
      guard readBack == data else {
        throw ExternalShareStoreError.readBackFailed(nil)
      }
      Self.log("requestId=\(requestId) attachment-write=success bytes=\(data.count)")
      return target.path
    } catch let error as ExternalShareStoreError {
      Self.log("requestId=\(requestId) \(error.code)")
      throw error
    } catch {
      Self.log("requestId=\(requestId) share-file-write-failed attachment error=\(error.localizedDescription)")
      throw ExternalShareStoreError.fileWriteFailed(error)
    }
  }

  func migrateLegacyDefaultsIfNeeded() {
    guard let defaults = UserDefaults(suiteName: Self.appGroupIdentifier),
          let raw = defaults.string(forKey: Self.legacyPendingKey),
          !raw.isEmpty else {
      return
    }

    Self.log("legacy-migration=start")
    guard let data = raw.data(using: .utf8),
          let values = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
      Self.log("legacy-migration=skipped share-json-decoding-failed")
      return
    }

    var migrationSucceeded = true
    for value in values {
      do {
        let itemData = try JSONSerialization.data(withJSONObject: value)
        let request = try decoder.decode(ExternalShareRequest.self, from: itemData)
        try validateRequestId(request.id)
        if try requestExists(id: request.id) {
          continue
        }
        if request.consumed {
          // Preserve legacy consumed semantics without reopening an already
          // handed-off draft. The normal retention cleanup removes it later.
          var consumedRequest = request
          consumedRequest.state = .pending
          let target = try requestURL(
            id: consumedRequest.id,
            directory: Self.pendingDirectoryName
          )
          try writeAndVerify(consumedRequest, to: target)
        } else {
          try savePending(request)
        }
      } catch {
        migrationSucceeded = false
        Self.log("legacy-migration-item-failed error=\(error.localizedDescription)")
      }
    }

    guard migrationSucceeded else {
      Self.log("legacy-migration=incomplete legacy-key-retained")
      return
    }
    defaults.removeObject(forKey: Self.legacyPendingKey)
    Self.log("legacy-migration=complete count=\(values.count)")
  }

  func pendingRequests() throws -> [ExternalShareRequest] {
    migrateLegacyDefaultsIfNeeded()
    try recoverStaleClaims()
    try pruneExpiredRequests()

    let claimed = try decodeRequests(in: Self.claimedDirectoryName)
    let claimedIds = Set(claimed.map(\.id))
    let pending = try decodeRequests(in: Self.pendingDirectoryName)
      .filter {
        !$0.consumed && $0.state == .pending && !claimedIds.contains($0.id)
      }
    // Runner가 작성 화면을 연 뒤 앱이 종료되어도 다음 실행에서 즉시 같은
    // requestId를 복원한다. Extension이 소유한 과거 claim은 stale recovery만
    // 적용하고 본 앱 작성 화면으로 선점하지 않는다.
    let resumableRunnerClaims = claimed.filter {
      $0.state == .runnerClaimed
    }
    let requests = (pending + resumableRunnerClaims)
      .sorted {
        if $0.receivedAtMillis != $1.receivedAtMillis {
          return $0.receivedAtMillis < $1.receivedAtMillis
        }
        return $0.id < $1.id
      }
    Self.log(
      "get-pending count=\(requests.count) resumedClaims=\(resumableRunnerClaims.count)"
    )
    return requests
  }

  @discardableResult
  func claim(id: String) throws -> ExternalShareRequest {
    try claim(id: id, owner: .runner)
  }

  @discardableResult
  func claim(id: String, owner: ExternalShareClaimOwner) throws -> ExternalShareRequest {
    try validateRequestId(id)
    let pendingURL = try requestURL(id: id, directory: Self.pendingDirectoryName)
    let claimedURL = try requestURL(id: id, directory: Self.claimedDirectoryName)

    if fileManager.fileExists(atPath: claimedURL.path) {
      let claimed = try decodeRequest(at: claimedURL)
      guard claimed.state == owner.state else {
        throw ExternalShareStoreError.requestAlreadyClaimed
      }
      if fileManager.fileExists(atPath: pendingURL.path) {
        try? fileManager.removeItem(at: pendingURL)
      }
      Self.log("requestId=\(id) claim=idempotent")
      return claimed
    }
    guard fileManager.fileExists(atPath: pendingURL.path) else {
      throw ExternalShareStoreError.requestNotFound
    }

    var request = try decodeRequest(at: pendingURL)
    request.state = owner.state
    request.consumed = true
    request.claimedAtMillis = Self.nowMillis
    try writeAndVerify(request, to: claimedURL)
    try fileManager.removeItem(at: pendingURL)
    Self.log("requestId=\(id) claim=success")
    return request
  }

  func complete(id: String, outcome: String) throws {
    try validateRequestId(id)
    switch outcome {
    case "posted", "discarded":
      let request = try existingRequest(id: id)
      try removeRequestFiles(id: id)
      removeAttachments(id: id, recordedPath: request?.imagePath)
      Self.log("requestId=\(id) complete=\(outcome)")
    case "failed":
      try releaseClaim(id: id)
      Self.log("requestId=\(id) complete=failed released-to-pending")
    default:
      throw ExternalShareStoreError.invalidOutcome
    }
  }

  func updateClaimedDraft(
    id: String,
    draftText: String,
    categoryKeys: [String],
    visibility: String,
    isAnonymous: Bool,
    visibleToCategoryIds: [String]
  ) throws {
    try validateRequestId(id)
    let claimedURL = try requestURL(id: id, directory: Self.claimedDirectoryName)
    guard fileManager.fileExists(atPath: claimedURL.path) else {
      throw ExternalShareStoreError.requestNotFound
    }
    var request = try decodeRequest(at: claimedURL)
    request.draftText = draftText
    request.categoryKeys = categoryKeys
    request.visibility = visibility
    request.isAnonymous = visibility == "public" && isAnonymous
    request.visibleToCategoryIds = visibility == "category" ? visibleToCategoryIds : []
    try writeAndVerify(request, to: claimedURL)
    Self.log("requestId=\(id) claimed-draft-update=success")
  }

  func dictionary(for request: ExternalShareRequest) throws -> [String: Any] {
    do {
      let data = try encoder.encode(request)
      guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw ExternalShareStoreError.jsonEncodingFailed(
          NSError(domain: "ExternalShareStore", code: 1)
        )
      }
      return value
    } catch let error as ExternalShareStoreError {
      throw error
    } catch {
      throw ExternalShareStoreError.jsonEncodingFailed(error)
    }
  }

  private func releaseClaim(id: String) throws {
    let claimedURL = try requestURL(id: id, directory: Self.claimedDirectoryName)
    guard fileManager.fileExists(atPath: claimedURL.path) else { return }
    var request = try decodeRequest(at: claimedURL)
    request.state = .pending
    request.consumed = false
    request.claimedAtMillis = nil
    let pendingURL = try requestURL(id: id, directory: Self.pendingDirectoryName)
    try writeAndVerify(request, to: pendingURL)
    try fileManager.removeItem(at: claimedURL)
  }

  private func recoverStaleClaims() throws {
    let cutoff = Self.nowMillis - Self.claimRecoveryMillis
    for request in try decodeRequests(in: Self.claimedDirectoryName) {
      guard (request.claimedAtMillis ?? request.receivedAtMillis) < cutoff else {
        continue
      }
      try releaseClaim(id: request.id)
      Self.log("requestId=\(request.id) stale-claim=recovered")
    }
  }

  private func pruneExpiredRequests() throws {
    let cutoff = Self.nowMillis - Self.requestLifetimeMillis
    for directory in [Self.pendingDirectoryName, Self.claimedDirectoryName] {
      for request in try decodeRequests(in: directory) where request.receivedAtMillis < cutoff {
        try removeRequestFiles(id: request.id)
        removeAttachments(id: request.id, recordedPath: request.imagePath)
        Self.log("requestId=\(request.id) expired=removed")
      }
    }
  }

  private func decodeRequests(in directoryName: String) throws -> [ExternalShareRequest] {
    let directory = try directoryURL(directoryName)
    let urls = try fileManager.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    ).filter { $0.pathExtension.lowercased() == "json" }

    var values: [ExternalShareRequest] = []
    for url in urls {
      do {
        let request = try decodeRequest(at: url)
        try validateRequestId(request.id)
        values.append(request)
      } catch {
        Self.log("corrupt-share-file=\(url.lastPathComponent) error=\(error.localizedDescription)")
        quarantine(url)
      }
    }
    return values
  }

  private func existingRequest(id: String) throws -> ExternalShareRequest? {
    for directory in [Self.claimedDirectoryName, Self.pendingDirectoryName] {
      let url = try requestURL(id: id, directory: directory)
      if fileManager.fileExists(atPath: url.path) {
        return try decodeRequest(at: url)
      }
    }
    return nil
  }

  private func requestExists(id: String) throws -> Bool {
    for directory in [Self.pendingDirectoryName, Self.claimedDirectoryName] {
      let url = try requestURL(id: id, directory: directory)
      if fileManager.fileExists(atPath: url.path) { return true }
    }
    return false
  }

  private func removeRequestFiles(id: String) throws {
    for directory in [Self.pendingDirectoryName, Self.claimedDirectoryName] {
      let url = try requestURL(id: id, directory: directory)
      if fileManager.fileExists(atPath: url.path) {
        try fileManager.removeItem(at: url)
      }
    }
  }

  private func removeAttachments(id: String, recordedPath: String?) {
    do {
      let directory = try directoryURL(Self.attachmentDirectoryName)
      let urls = try fileManager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )
      for url in urls where url.deletingPathExtension().lastPathComponent == id {
        try? fileManager.removeItem(at: url)
      }

      if let recordedPath, !recordedPath.isEmpty {
        let root = try rootURL().standardizedFileURL.path
        let recorded = URL(fileURLWithPath: recordedPath).standardizedFileURL
        if recorded.path.hasPrefix(root + "/") {
          try? fileManager.removeItem(at: recorded)
        }
      }
    } catch {
      Self.log("requestId=\(id) attachment-cleanup-failed error=\(error.localizedDescription)")
    }
  }

  private func quarantine(_ source: URL) {
    do {
      let directory = try directoryURL(Self.corruptDirectoryName)
      let target = directory.appendingPathComponent(
        "\(source.deletingPathExtension().lastPathComponent)-\(UUID().uuidString).json"
      )
      try fileManager.moveItem(at: source, to: target)
    } catch {
      try? fileManager.removeItem(at: source)
    }
  }

  private func writeAndVerify(_ request: ExternalShareRequest, to target: URL) throws {
    let data: Data
    do {
      data = try encoder.encode(request)
      Self.log("requestId=\(request.id) json-encoding=success")
    } catch {
      Self.log("requestId=\(request.id) share-json-encoding-failed error=\(error.localizedDescription)")
      throw ExternalShareStoreError.jsonEncodingFailed(error)
    }

    do {
      try data.write(to: target, options: .atomic)
      Self.log("requestId=\(request.id) atomic-write=success")
    } catch {
      Self.log("requestId=\(request.id) share-file-write-failed error=\(error.localizedDescription)")
      throw ExternalShareStoreError.fileWriteFailed(error)
    }

    do {
      let readBack = try Data(contentsOf: target)
      let decoded = try decoder.decode(ExternalShareRequest.self, from: readBack)
      guard decoded.id == request.id else {
        throw ExternalShareStoreError.readBackFailed(nil)
      }
      Self.log("requestId=\(request.id) readback=success")
    } catch let error as ExternalShareStoreError {
      Self.log("requestId=\(request.id) \(error.code)")
      throw error
    } catch {
      Self.log("requestId=\(request.id) share-readback-failed error=\(error.localizedDescription)")
      throw ExternalShareStoreError.readBackFailed(error)
    }
  }

  private func decodeRequest(at url: URL) throws -> ExternalShareRequest {
    let data = try Data(contentsOf: url)
    return try decoder.decode(ExternalShareRequest.self, from: data)
  }

  private func requestURL(id: String, directory: String) throws -> URL {
    try validateRequestId(id)
    return try directoryURL(directory).appendingPathComponent("\(id).json")
  }

  private func directoryURL(_ name: String) throws -> URL {
    let directory = try rootURL().appendingPathComponent(name, isDirectory: true)
    do {
      try fileManager.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: nil
      )
      return directory
    } catch {
      Self.log("share-directory-create-failed name=\(name) error=\(error.localizedDescription)")
      throw ExternalShareStoreError.fileWriteFailed(error)
    }
  }

  private func rootURL() throws -> URL {
    guard let container = fileManager.containerURL(
      forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
    ) else {
      Self.log("app-group-container-unavailable appGroup=\(Self.appGroupIdentifier)")
      throw ExternalShareStoreError.containerUnavailable
    }
    Self.log("appGroup=\(Self.appGroupIdentifier) containerAvailable=true")
    let root = container.appendingPathComponent(Self.rootDirectoryName, isDirectory: true)
    do {
      try fileManager.createDirectory(
        at: root,
        withIntermediateDirectories: true,
        attributes: nil
      )
      return root
    } catch {
      throw ExternalShareStoreError.fileWriteFailed(error)
    }
  }

  private func validateRequestId(_ id: String) throws {
    guard id.range(
      of: "^[A-Za-z0-9_-]{1,128}$",
      options: .regularExpression
    ) != nil else {
      throw ExternalShareStoreError.invalidRequestId
    }
  }

  private static var nowMillis: Int64 {
    Int64(Date().timeIntervalSince1970 * 1_000)
  }

  private static func log(_ message: String) {
    NSLog("[ExternalShare][Store] %@", message)
  }
}
