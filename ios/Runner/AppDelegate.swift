import Flutter
import Photos
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var mediaSaverChannel: FlutterMethodChannel?
  private var isSavingMedia = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // iOS 시작 시점에 Firebase Keychain/UserDefaults를 강제로 삭제하면
    // Messaging/Installations 초기화와 충돌할 수 있으므로 더 이상 수행하지 않는다.

    // UNUserNotificationCenter delegate 설정
    // 이것은 firebase_messaging 플러그인과 함께 작동하며,
    // 포어그라운드 알림 표시를 위해 필수입니다
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    }

    // 중요: iOS 앱 시작 시점에는 APNs 등록을 즉시 호출하지 않는다.
    // 푸시 활성화는 Flutter 레이어의 상태 머신(locale/session/active/권한) 이후에 진행한다.
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

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
    print("📱 포어그라운드 알림 수신: \(userInfo)")

    // 포그라운드에서는 시스템 배너/사운드를 띄우지 않는다.
    // 실제 표시 여부는 Flutter(fcm_service)의 로컬 알림 정책에서 제어한다.
    completionHandler([])
  }
  
  // 알림을 탭했을 때 호출됨 (백그라운드/종료 상태)
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    print("📱 알림 탭: \(userInfo)")
    
    // firebase_messaging 플러그인이 자동으로 처리
    completionHandler()
  }
}
