import Flutter
import UIKit
import Foundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let shareChannelName = "com.wefilling.app/share"
  private var methodChannel: FlutterMethodChannel?
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    if let controller = window?.rootViewController as? FlutterViewController {
      methodChannel = FlutterMethodChannel(name: shareChannelName, binaryMessenger: controller.binaryMessenger)
      methodChannel?.setMethodCallHandler({ [weak self] call, result in
        guard let self = self else { return }
        switch call.method {
        case "fetchPendingShare":
          NSLog("📥 AppDelegate: fetchPendingShare 호출됨")
          if let paths = self.readPendingSharePaths(), !paths.isEmpty {
            // 페이로드는 소비되었음을 표시(중복 방지)하되, 파일은 Dart에서 복사 후 별도 정리 요청
            self.clearPayloadJson()
            NSLog("📥 AppDelegate: 공유 페이로드 발견 - \(paths.count)개")
            result(paths)
          } else {
            NSLog("📭 AppDelegate: 대기 중인 공유 페이로드 없음")
            result([String]())
          }
        case "cleanupSharedFiles":
          if let list = call.arguments as? [String] {
            NSLog("🧹 AppDelegate: cleanupSharedFiles 호출 - \(list.count)개 정리 예정")
            self.cleanup(paths: list)
            result(true)
          } else {
            result(false)
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      })
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  override func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
    NSLog("🔗 AppDelegate: URL 열기 요청 받음 - \(url.absoluteString)")
    if !options.isEmpty {
      NSLog("🔗 AppDelegate: URL 옵션 - \(options)")
    }
    
    // 파일 URL로 열렸을 때 (사진 앱에서 "Wefilling에서 열기" 선택)
    if url.isFileURL {
      NSLog("📸 AppDelegate: 파일로 앱 열림 - \(url.path)")
      
      // 이미지 파일인지 확인
      let imageExtensions = ["jpg", "jpeg", "png", "heic", "heif"]
      let fileExtension = url.pathExtension.lowercased()
      
      if imageExtensions.contains(fileExtension) {
        // 파일을 앱의 임시 디렉토리로 복사
        do {
          let tempDir = FileManager.default.temporaryDirectory
          let fileName = "opened_\(UUID().uuidString).\(fileExtension)"
          let destURL = tempDir.appendingPathComponent(fileName)
          
          // 기존 파일이 있으면 삭제
          if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
          }
          
          // 파일 복사
          try FileManager.default.copyItem(at: url, to: destURL)
          
          NSLog("✅ AppDelegate: 이미지 파일 복사 완료 - \(destURL.path)")
          
          // Flutter로 전달
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.methodChannel?.invokeMethod("sharedImages", arguments: [destURL.path])
          }
          
          return true
        } catch {
          NSLog("❌ AppDelegate: 파일 복사 실패 - \(error.localizedDescription)")
        }
      }
    }
    
    // wefilling://compose 로 열렸을 때 Dart에 알림
    if url.scheme == "wefilling" && url.host == "compose" {
      NSLog("✅ AppDelegate: wefilling://compose URL 감지됨")
      
      // 공유 데이터가 있는지 확인하고 Dart로 전달
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        if let paths = self.readPendingSharePaths(), !paths.isEmpty {
          NSLog("📸 AppDelegate: 공유 이미지 발견 - \(paths.count)개")
          self.methodChannel?.invokeMethod("sharedImages", arguments: paths)
          self.clearPayloadJson()
        } else {
          NSLog("⚠️ AppDelegate: 공유 이미지 없음")
        }
      }
      return true
    }
    return super.application(app, open: url, options: options)
  }
  
  override func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
    // NSUserActivity를 통한 앱 열기 처리
    if userActivity.activityType == "com.wefilling.app.compose" {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        if let paths = self.readPendingSharePaths(), !paths.isEmpty {
          self.methodChannel?.invokeMethod("sharedImages", arguments: paths)
          self.clearPayloadJson()
        }
      }
      return true
    }
    return super.application(application, continue: userActivity, restorationHandler: restorationHandler)
  }
  
  private func readPendingSharePaths() -> [String]? {
    guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.wefilling") else { return nil }
    let shareDir = containerURL.appendingPathComponent("Shared/IncomingShare", isDirectory: true)
    let payloadURL = shareDir.appendingPathComponent("payload.json")
    guard let data = try? Data(contentsOf: payloadURL),
          let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
          let paths = json["paths"] as? [String],
          !paths.isEmpty else { return nil }
    return paths
  }
  
  private func cleanup(paths: [String]) {
    for p in paths {
      try? FileManager.default.removeItem(atPath: p)
    }
  }
  
  private func clearPayloadJson() {
    guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.wefilling") else { return }
    let shareDir = containerURL.appendingPathComponent("Shared/IncomingShare", isDirectory: true)
    let payloadURL = shareDir.appendingPathComponent("payload.json")
    try? FileManager.default.removeItem(at: payloadURL)
  }
}
