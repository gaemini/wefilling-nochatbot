import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // UNUserNotificationCenter delegate 설정
    // 이것은 firebase_messaging 플러그인과 함께 작동하며,
    // 포어그라운드 알림 표시를 위해 필수입니다
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    }
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
    
    // iOS 14 이상
    if #available(iOS 14.0, *) {
      completionHandler([[.banner, .badge, .sound]])
    }
    // iOS 10-13
    else {
      completionHandler([[.alert, .badge, .sound]])
    }
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
