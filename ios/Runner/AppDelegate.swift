import Flutter
import FirebaseAuth
import FirebaseCore
import Photos
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var mediaSaverChannel: FlutterMethodChannel?
  private var externalShareChannel: FlutterMethodChannel?
  private var sharedFirebaseAuthChannel: FlutterMethodChannel?
  private var isSavingMedia = false
  private let externalShareStore = ExternalShareStore()
  private var externalShareBridgeReady = false
  private var pendingShareWakeRequest = false
  private var pendingShareRequestId: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // iOS 시작 시점에 Firebase Keychain/UserDefaults를 강제로 삭제하면
    // Messaging/Installations 초기화와 충돌할 수 있으므로 더 이상 수행하지 않는다.

    Self.externalShareLog(
      "bundleId=\(Bundle.main.bundleIdentifier ?? "unknown") appGroup=\(ExternalShareStore.appGroupIdentifier) launch=start"
    )
    externalShareStore.migrateLegacyDefaultsIfNeeded()

    // 중요: iOS 앱 시작 시점에는 APNs 등록을 즉시 호출하지 않는다.
    // 푸시 활성화는 Flutter 레이어의 상태 머신(locale/session/active/권한) 이후에 진행한다.
    
    let launched = super.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )
    // Flutter/Firebase 플러그인 등록 이후 최종 delegate를 Runner로 고정해야
    // 종료 상태에서 외부 공유 로컬 알림 탭도 이 AppDelegate로 전달된다.
    UNUserNotificationCenter.current().delegate = self
    return launched
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let authChannel = FlutterMethodChannel(
      name: "com.wefilling.app/shared_firebase_auth",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    authChannel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "enableSharedAuth" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.enableSharedFirebaseAuth(result: result)
    }
    sharedFirebaseAuthChannel = authChannel

    let channel = FlutterMethodChannel(
      name: "com.wefilling.app/media_saver",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "saveImage" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.saveImageToPhotos(call: call, result: result)
    }
    mediaSaverChannel = channel

    let shareChannel = FlutterMethodChannel(
      name: "com.wefilling.app/external_share",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    externalShareBridgeReady = false
    shareChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "share-unavailable", message: nil, details: nil))
        return
      }
      switch call.method {
      case "shareBridgeReady":
        self.externalShareBridgeReady = true
        Self.externalShareLog(
          "bridge-ready=true pendingWake=\(self.pendingShareWakeRequest)"
        )
        self.deliverExternalShareWakeIfPossible()
        result(nil)
      case "getPendingShares":
        do {
          let requests = try self.externalShareStore.pendingRequests()
          let values = try requests.map { try self.externalShareStore.dictionary(for: $0) }
          Self.externalShareLog("getPendingShares count=\(values.count)")
          result(values)
        } catch {
          let code = (error as? ExternalShareStoreError)?.code ?? "share-read-failed"
          Self.externalShareLog(
            "getPendingShares failed code=\(code) error=\(error.localizedDescription)"
          )
          result(FlutterError(code: code, message: "Could not read pending shares.", details: nil))
        }
      case "consumeShare":
        guard let arguments = call.arguments as? [String: Any],
              let id = arguments["id"] as? String,
              !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          result(FlutterError(code: "invalid-share-id", message: "Share id is required.", details: nil))
          return
        }
        do {
          _ = try self.externalShareStore.claim(id: id)
          Self.externalShareLog("requestId=\(id) consumeShare=success")
          result(true)
        } catch {
          let code = (error as? ExternalShareStoreError)?.code ?? "share-claim-failed"
          Self.externalShareLog(
            "requestId=\(id) consumeShare=failed code=\(code) error=\(error.localizedDescription)"
          )
          result(FlutterError(code: code, message: "Could not claim share.", details: nil))
        }
      case "completeShareFlow":
        guard let arguments = call.arguments as? [String: Any],
              let id = arguments["id"] as? String,
              !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let outcome = arguments["outcome"] as? String else {
          result(FlutterError(
            code: "invalid-share-completion",
            message: "Share id and outcome are required.",
            details: nil
          ))
          return
        }
        do {
          try self.externalShareStore.complete(id: id, outcome: outcome)
          Self.externalShareLog(
            "requestId=\(id) completeShareFlow=success outcome=\(outcome)"
          )
          result(true)
        } catch {
          let code = (error as? ExternalShareStoreError)?.code ?? "share-completion-failed"
          Self.externalShareLog(
            "requestId=\(id) completeShareFlow=failed outcome=\(outcome) code=\(code)"
          )
          result(FlutterError(code: code, message: "Could not complete share.", details: nil))
        }
      case "updateShareDraft":
        guard let arguments = call.arguments as? [String: Any],
              let id = arguments["id"] as? String,
              !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          result(FlutterError(
            code: "invalid-share-draft",
            message: "Share id is required.",
            details: nil
          ))
          return
        }
        do {
          try self.externalShareStore.updateClaimedDraft(
            id: id,
            draftText: (arguments["draftText"] as? String) ?? "",
            categoryKeys: (arguments["categoryKeys"] as? [String]) ?? [],
            visibility: (arguments["visibility"] as? String) ?? "public",
            isAnonymous: (arguments["isAnonymous"] as? Bool) ?? false,
            visibleToCategoryIds: (arguments["visibleToCategoryIds"] as? [String]) ?? []
          )
          Self.externalShareLog("requestId=\(id) draft-update=success")
          result(true)
        } catch {
          let code = (error as? ExternalShareStoreError)?.code ?? "share-draft-update-failed"
          Self.externalShareLog("requestId=\(id) draft-update=failed code=\(code)")
          result(FlutterError(code: code, message: "Could not save share draft.", details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    externalShareChannel = shareChannel
    Self.externalShareLog("method-channel=created bridge-ready=false")
  }

  private func enableSharedFirebaseAuth(result: @escaping FlutterResult) {
    let accessGroup = "ULTS66B6QD.com.wefilling.app"
    guard FirebaseApp.app() != nil else {
      result(FlutterError(
        code: "firebase-not-configured",
        message: "Firebase must be configured before sharing Auth state.",
        details: nil
      ))
      return
    }

    let auth = Auth.auth()
    if auth.userAccessGroup == accessGroup {
      result(nil)
      return
    }

    let currentUser = auth.currentUser
    do {
      _ = try auth.getStoredUser(forAccessGroup: accessGroup)
      try auth.useUserAccessGroup(accessGroup)
    } catch {
      result(FlutterError(
        code: "shared-auth-keychain-unavailable",
        message: error.localizedDescription,
        details: nil
      ))
      return
    }

    guard let currentUser,
          auth.currentUser?.uid != currentUser.uid else {
      result(nil)
      return
    }

    // Firebase clears the unshared current user while switching access groups.
    // Re-persist the retained User object into the shared Keychain exactly as
    // described by Firebase's cross-app authentication migration flow.
    auth.updateCurrentUser(currentUser) { error in
      guard let error else {
        result(nil)
        return
      }

      // Migration must never silently log out an existing installation. If the
      // shared write fails, restore the previous unshared session and let the
      // Share Extension use its signed-out fallback until a later retry.
      do {
        try auth.useUserAccessGroup(nil)
        auth.updateCurrentUser(currentUser) { _ in
          result(FlutterError(
            code: "shared-auth-migration-failed",
            message: error.localizedDescription,
            details: nil
          ))
        }
      } catch {
        result(FlutterError(
          code: "shared-auth-rollback-failed",
          message: error.localizedDescription,
          details: nil
        ))
      }
    }
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    requestExternalShareWake(source: "application-did-become-active")
  }

  private func requestExternalShareWake(source: String, requestId: String? = nil) {
    if !Thread.isMainThread {
      DispatchQueue.main.async { [weak self] in
        self?.requestExternalShareWake(source: source, requestId: requestId)
      }
      return
    }
    if let requestId,
       !requestId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      pendingShareRequestId = requestId
    }
    pendingShareWakeRequest = true
    Self.externalShareLog(
      "wake-request source=\(source) requestId=\(pendingShareRequestId ?? "none") bridgeReady=\(externalShareBridgeReady)"
    )
    deliverExternalShareWakeIfPossible()
  }

  private func deliverExternalShareWakeIfPossible() {
    guard pendingShareWakeRequest,
          externalShareBridgeReady,
          let externalShareChannel else {
      return
    }
    pendingShareWakeRequest = false
    let requestId = pendingShareRequestId
    pendingShareRequestId = nil
    Self.externalShareLog("shareReceived=delivered requestId=\(requestId ?? "none")")
    externalShareChannel.invokeMethod(
      "shareReceived",
      arguments: requestId.map { ["externalShareRequestId": $0] }
    )
  }

  private func saveImageToPhotos(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let arguments = call.arguments as? [String: Any],
      let typedData = arguments["bytes"] as? FlutterStandardTypedData,
      !typedData.data.isEmpty
    else {
      result(FlutterError(
        code: "invalid-image-data",
        message: "Image bytes are required.",
        details: nil
      ))
      return
    }
    let filename = (arguments["filename"] as? String)?.trimmingCharacters(
      in: .whitespacesAndNewlines
    ) ?? "wefilling.jpg"
    guard !isSavingMedia else {
      result(FlutterError(
        code: "save-in-progress",
        message: "Another image save is in progress.",
        details: nil
      ))
      return
    }
    isSavingMedia = true

    requestPhotoAddPermission { [weak self] granted in
      guard granted else {
        DispatchQueue.main.async {
          self?.isSavingMedia = false
          result(FlutterError(
            code: "photo-permission-denied",
            message: "Photo add permission was denied.",
            details: nil
          ))
        }
        return
      }
      self?.performPhotoSave(
        data: typedData.data,
        filename: filename.isEmpty ? "wefilling.jpg" : filename,
        result: result
      )
    }
  }

  private func requestPhotoAddPermission(completion: @escaping (Bool) -> Void) {
    if #available(iOS 14, *) {
      let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
      if status == .notDetermined {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { nextStatus in
          completion(nextStatus == .authorized || nextStatus == .limited)
        }
      } else {
        completion(status == .authorized || status == .limited)
      }
      return
    }
    let status = PHPhotoLibrary.authorizationStatus()
    if status == .notDetermined {
      PHPhotoLibrary.requestAuthorization { nextStatus in
        completion(nextStatus == .authorized)
      }
    } else {
      completion(status == .authorized)
    }
  }

  private func performPhotoSave(
    data: Data,
    filename: String,
    result: @escaping FlutterResult
  ) {
    let options = PHAssetResourceCreationOptions()
    options.originalFilename = filename
    PHPhotoLibrary.shared().performChanges({
      let request = PHAssetCreationRequest.forAsset()
      request.addResource(with: .photo, data: data, options: options)
    }) { success, error in
      DispatchQueue.main.async {
        self.isSavingMedia = false
        if success {
          result(nil)
        } else {
          result(FlutterError(
            code: "photo-save-failed",
            message: error?.localizedDescription ?? "Could not save the image.",
            details: nil
          ))
        }
      }
    }
  }
  
  
  // 포어그라운드에서 알림을 받았을 때 호출됨
  // 이 메서드가 없으면 포어그라운드에서 알림이 표시되지 않음
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let userInfo = notification.request.content.userInfo
    if (userInfo["type"] as? String) == "external_share" {
      let requestId = userInfo["externalShareRequestId"] as? String
      requestExternalShareWake(
        source: "foreground-external-share-notification",
        requestId: requestId
      )
      completionHandler([])
      return
    }

    // 일반 FCM은 FlutterAppDelegate까지 반드시 전달해야 firebase_messaging의
    // onMessage 스트림과 foreground presentation 설정이 함께 동작한다.
    super.userNotificationCenter(
      center,
      willPresent: notification,
      withCompletionHandler: completionHandler
    )
  }
  
  // 알림을 탭했을 때 호출됨 (백그라운드/종료 상태)
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    if (userInfo["type"] as? String) == "external_share" {
      let requestId = (userInfo["externalShareRequestId"] as? String) ?? "unknown"
      Self.externalShareLog("requestId=\(requestId) notification-tap=external-share")
      requestExternalShareWake(
        source: "external-share-notification-tap",
        requestId: requestId == "unknown" ? nil : requestId
      )
      completionHandler()
      return
    }

    // 일반 FCM/로컬 알림은 기존 firebase_messaging 처리 경로로 전달한다.
    super.userNotificationCenter(
      center,
      didReceive: response,
      withCompletionHandler: completionHandler
    )
  }

  private static func externalShareLog(_ message: String) {
    NSLog("[ExternalShare][Runner] %@", message)
  }
}
