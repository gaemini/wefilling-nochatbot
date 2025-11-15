import UIKit
import Social
import UniformTypeIdentifiers
import MobileCoreServices
import SafariServices

class ShareViewController: UIViewController {
	
	private let titleLabel: UILabel = {
		let lb = UILabel()
		lb.text = "Wefilling로 공유"
		lb.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
		lb.textAlignment = .center
		return lb
	}()
	
	private let detailLabel: UILabel = {
		let lb = UILabel()
		lb.text = "앱으로 이동하여 게시글 작성 화면을 엽니다."
		lb.font = UIFont.systemFont(ofSize: 14, weight: .regular)
		lb.textColor = .secondaryLabel
		lb.numberOfLines = 2
		lb.textAlignment = .center
		return lb
	}()
	
	private let activity = UIActivityIndicatorView(style: .medium)
	private let continueButton: UIButton = {
		let bt = UIButton(type: .system)
		bt.setTitle("앱에서 계속", for: .normal)
		bt.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
		bt.backgroundColor = UIColor.systemBlue
		bt.setTitleColor(.white, for: .normal)
		bt.layer.cornerRadius = 10
		bt.isEnabled = false
		bt.alpha = 0.6
		return bt
	}()
	
	private var savedPaths: [String] = []
	
	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = UIColor.systemBackground
		layoutUI()
		activity.startAnimating()
		processAttachments()
	}
	
	private func layoutUI() {
		[titleLabel, detailLabel, activity, continueButton].forEach { v in
			v.translatesAutoresizingMaskIntoConstraints = false
			view.addSubview(v)
		}
		NSLayoutConstraint.activate([
			titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
			titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
			titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
			
			detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
			detailLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
			detailLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
			
			activity.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 16),
			activity.centerXAnchor.constraint(equalTo: view.centerXAnchor),
			
			continueButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
			continueButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
			continueButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
			continueButton.heightAnchor.constraint(equalToConstant: 48)
		])
		continueButton.addTarget(self, action: #selector(onContinue), for: .touchUpInside)
	}
	
	private func setReady() {
		activity.stopAnimating()
		continueButton.isEnabled = true
		continueButton.alpha = 1.0
	}
	
	private func processAttachments() {
		guard let extensionItems = self.extensionContext?.inputItems as? [NSExtensionItem] else {
			self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
			return
		}
		var imageProviders: [NSItemProvider] = []
		for item in extensionItems {
			let attachments = item.attachments ?? []
			for provider in attachments {
				if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
					imageProviders.append(provider)
				}
			}
		}
		if imageProviders.isEmpty {
			self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
			return
		}
		saveProviders(providers: imageProviders)
	}
	
	private func saveProviders(providers: [NSItemProvider]) {
		guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.wefilling") else {
			self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
			return
		}
		let shareDir = containerURL.appendingPathComponent("Shared/IncomingShare", isDirectory: true)
		try? FileManager.default.createDirectory(at: shareDir, withIntermediateDirectories: true, attributes: nil)
		
		let group = DispatchGroup()
		var paths: [String] = []
		
		for provider in providers {
			group.enter()
			provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
				defer { group.leave() }
				guard let srcURL = url else { return }
				let filename = "img_\(UUID().uuidString)\(srcURL.pathExtension.isEmpty ? ".jpg" : ".\(srcURL.pathExtension)")"
				let dstURL = shareDir.appendingPathComponent(filename)
				do {
					if FileManager.default.fileExists(atPath: dstURL.path) {
						try FileManager.default.removeItem(at: dstURL)
					}
					try FileManager.default.copyItem(at: srcURL, to: dstURL)
					paths.append(dstURL.path)
				} catch {
					// ignore copy error
				}
			}
		}
		
		group.notify(queue: .main) { [weak self] in
			guard let self = self else { return }
			self.savedPaths = paths
			// 기록 파일 작성
			let payloadURL = shareDir.appendingPathComponent("payload.json")
			let dict: [String: Any] = ["paths": paths, "timestamp": Date().timeIntervalSince1970]
			if let data = try? JSONSerialization.data(withJSONObject: dict, options: []) {
				try? data.write(to: payloadURL, options: .atomic)
			}
			self.setReady()
			
			// UI 업데이트 - 성공 메시지 표시
			self.detailLabel.text = "이미지가 저장되었습니다!"
			self.detailLabel.textColor = .systemGreen
			self.continueButton.setTitle("앱에서 게시글 작성", for: .normal)
			
			// 즉시 앱 열기 시도
			self.openHostAppAndComplete()
		}
	}
	
	@objc private func onContinue() {
		openHostAppAndComplete()
	}
	
	private func openHostAppAndComplete() {
		let urlString = "wefilling://compose?source=share&ts=\(Int(Date().timeIntervalSince1970))"
		guard let openURL = URL(string: urlString) else {
			self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
			return
		}
		
		NSLog("🔗 Wefilling Share Extension: 앱 열기 시도 - \(urlString)")
		
		// extensionContext open을 사용하여 앱 열기
		self.extensionContext?.open(openURL, completionHandler: { [weak self] success in
			NSLog("✅ Wefilling Share Extension: URL 열기 결과 = \(success)")
			
			// URL 열기 성공/실패와 관계없이 Extension을 종료
			// 중요: completeRequest를 너무 빨리 호출하면 URL 열기가 취소될 수 있음
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
				self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: { _ in
					NSLog("🏁 Wefilling Share Extension: Extension 종료 완료")
				})
			}
			
			// 실패 시 사용자 안내 및 버튼 활성화(수동 시도로 전환)
			if success == false {
				DispatchQueue.main.async {
					self?.detailLabel.text = "앱 열기에 실패했습니다. 아래 버튼을 눌러 앱에서 계속하세요."
					self?.detailLabel.textColor = .systemOrange
					self?.setReady()
				}
			}
		})
	}
}


