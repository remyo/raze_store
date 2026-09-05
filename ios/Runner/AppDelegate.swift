import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var receiptExportChannel: FlutterMethodChannel?
  private var receiptDocumentExporter: ReceiptDocumentExporter?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let exporter = ReceiptDocumentExporter()
    receiptDocumentExporter = exporter

    let channel = FlutterMethodChannel(
      name: "com.remyo.raze_store/receipt_export",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak exporter] call, result in
      guard let exporter else {
        result(
          FlutterError(
            code: "exporter_unavailable",
            message: "The receipt exporter is unavailable.",
            details: nil
          )
        )
        return
      }
      exporter.handle(call, result: result)
    }
    receiptExportChannel = channel
  }
}

/// Presents the iOS document exporter from the active scene.
///
/// The third-party file-dialog plugin still relies on `UIApplication.keyWindow`,
/// which can be nil for scene-based Flutter apps. Keeping this small exporter in
/// the host app makes receipt downloads reliable on iOS 16 and later.
private final class ReceiptDocumentExporter: NSObject,
  UIDocumentPickerDelegate,
  UIAdaptivePresentationControllerDelegate
{
  private var pendingResult: FlutterResult?
  private var exportDirectory: URL?

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "saveReceipt" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard pendingResult == nil else {
      result(
        FlutterError(
          code: "export_in_progress",
          message: "Another receipt download is already open.",
          details: nil
        )
      )
      return
    }
    guard
      let arguments = call.arguments as? [String: Any],
      let sourcePath = arguments["sourcePath"] as? String,
      let fileName = arguments["fileName"] as? String,
      !sourcePath.isEmpty,
      !fileName.isEmpty
    else {
      result(
        FlutterError(
          code: "invalid_arguments",
          message: "The receipt file information is incomplete.",
          details: nil
        )
      )
      return
    }

    let sourceURL = URL(fileURLWithPath: sourcePath).standardizedFileURL
    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
      result(
        FlutterError(
          code: "file_not_found",
          message: "The prepared receipt file could not be found.",
          details: nil
        )
      )
      return
    }

    do {
      let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("raze-store-receipt-export-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
      )
      let exportURL = directory.appendingPathComponent(fileName, isDirectory: false)
      try FileManager.default.copyItem(at: sourceURL, to: exportURL)

      guard let presenter = Self.activePresenter() else {
        try? FileManager.default.removeItem(at: directory)
        result(
          FlutterError(
            code: "presenter_unavailable",
            message: "Could not open Files from the current screen.",
            details: nil
          )
        )
        return
      }

      pendingResult = result
      exportDirectory = directory

      let picker = UIDocumentPickerViewController(
        forExporting: [exportURL],
        asCopy: true
      )
      picker.delegate = self
      picker.presentationController?.delegate = self
      presenter.present(picker, animated: true) { [weak self, weak picker] in
        picker?.presentationController?.delegate = self
      }
    } catch {
      cleanUpExport()
      result(
        FlutterError(
          code: "prepare_failed",
          message: "Could not prepare the receipt for Files.",
          details: error.localizedDescription
        )
      )
    }
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    finish(with: urls.first?.path)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(with: nil)
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    finish(with: nil)
  }

  private func finish(with value: String?) {
    guard let result = pendingResult else { return }
    pendingResult = nil
    cleanUpExport()
    result(value)
  }

  private func cleanUpExport() {
    if let exportDirectory {
      try? FileManager.default.removeItem(at: exportDirectory)
    }
    exportDirectory = nil
  }

  private static func activePresenter() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .sorted { lhs, rhs in
        activationPriority(lhs.activationState) > activationPriority(rhs.activationState)
      }

    for scene in scenes {
      let window = scene.windows.first(where: { $0.isKeyWindow })
        ?? scene.windows.first(where: { !$0.isHidden && $0.alpha > 0 })
      if let root = window?.rootViewController {
        return topViewController(from: root)
      }
    }
    return nil
  }

  private static func activationPriority(_ state: UIScene.ActivationState) -> Int {
    switch state {
    case .foregroundActive:
      return 3
    case .foregroundInactive:
      return 2
    case .background:
      return 1
    case .unattached:
      return 0
    @unknown default:
      return 0
    }
  }

  private static func topViewController(from root: UIViewController) -> UIViewController {
    if let presented = root.presentedViewController,
      !presented.isBeingDismissed
    {
      return topViewController(from: presented)
    }
    if let navigation = root as? UINavigationController,
      let visible = navigation.visibleViewController
    {
      return topViewController(from: visible)
    }
    if let tabs = root as? UITabBarController,
      let selected = tabs.selectedViewController
    {
      return topViewController(from: selected)
    }
    for child in root.children.reversed() where child.viewIfLoaded?.window != nil {
      return topViewController(from: child)
    }
    return root
  }
}
