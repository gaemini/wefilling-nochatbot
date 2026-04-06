import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // ✅ PHASE 4: Keychain 정리 추가 (최우선 실행)
    cleanupFirebaseKeychain()
    // ✅ PHASE 1: UserDefaults 캐시 정리
    cleanupFirebaseMessagingCache()
    
    // UNUserNotificationCenter delegate 설정
    // 이것은 firebase_messaging 플러그인과 함께 작동하며,
    // 포어그라운드 알림 표시를 위해 필수입니다
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    }
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // PHASE 4: Firebase Keychain 데이터 정리
  private func cleanupFirebaseKeychain() {
    let keychainQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.firebase.installations"
    ]
    
    let status = SecItemDelete(keychainQuery as CFDictionary)
    if status == errSecSuccess {
      print("🔑 Firebase Keychain 정리 완료")
    } else if status == errSecItemNotFound {
      print("🔑 Firebase Keychain 항목 없음 (정상)")
    } else {
      print("⚠️ Keychain 정리 실패: \(status) (무시)")
    }
  }
  
  // Firebase Messaging 손상된 캐시 정리
  private func cleanupFirebaseMessagingCache() {
    let defaults = UserDefaults.standard
    
    // Firebase Messaging이 저장하는 내부 캐시 키들
    let keysToRemove = [
      "com.google.gcm.checkin_device_data",  // GCM 체크인 데이터
      "com.firebase.messaging",               // FCM 메인 데이터
      "com.google.iid"                        // Instance ID
    ]
    
    var removedCount = 0
    for key in keysToRemove {
      if defaults.object(forKey: key) != nil {
        defaults.removeObject(forKey: key)
        removedCount += 1
      }
    }
    
    defaults.synchronize()
    print("🧹 Firebase Messaging 캐시 정리: \(removedCount)개 항목 삭제")
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
