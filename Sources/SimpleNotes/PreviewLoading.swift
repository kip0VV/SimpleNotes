import Cocoa
import WebKit

final class PreviewStatusView: NSView {
  let spinner = NSProgressIndicator()
  let message = NSTextField(labelWithString: "Загружаем заметку…")
  let detail = NSTextField(wrappingLabelWithString: "Подготавливаем текст и формулы")
  let retry = NSButton(title: "Повторить", target: nil, action: nil)

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    spinner.style = .spinning
    spinner.controlSize = .regular
    spinner.isDisplayedWhenStopped = false
    message.font = .systemFont(ofSize: 16, weight: .medium)
    message.alignment = .center
    detail.font = .systemFont(ofSize: 13)
    detail.textColor = .secondaryLabelColor
    detail.alignment = .center
    retry.bezelStyle = .rounded
    let stack = NSStackView(views: [spinner, message, detail, retry])
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
      stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
      detail.widthAnchor.constraint(lessThanOrEqualToConstant: 340),
      spinner.widthAnchor.constraint(equalToConstant: 28),
      spinner.heightAnchor.constraint(equalToConstant: 28),
    ])
    isHidden = true
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

extension NotesApp {
  func preparePreviewStatus() {
    if previewStatus.superview == nil {
      previewStatus.translatesAutoresizingMaskIntoConstraints = false
      previewContainer.addSubview(previewStatus)
      NSLayoutConstraint.activate([
        previewStatus.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
        previewStatus.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
        previewStatus.topAnchor.constraint(equalTo: previewContainer.topAnchor),
        previewStatus.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),
      ])
      previewStatus.retry.target = self
      previewStatus.retry.action = #selector(retryMarkdownPreview)
    }
    previewStatus.layer?.backgroundColor = (EditorStyle.color(editorBackgroundHex) ?? .textBackgroundColor).cgColor
  }

  func showPreviewLoading(immediately: Bool) {
    previewStatusWork?.cancel()
    let generation = previewRenderGeneration
    let show = { [weak self] in
      guard let self = self, generation == self.previewRenderGeneration else { return }
      self.preparePreviewStatus()
      self.previewStatus.message.stringValue = "Загружаем заметку…"
      self.previewStatus.detail.stringValue = "Подготавливаем текст и формулы"
      self.previewStatus.retry.isHidden = true
      self.previewStatus.spinner.startAnimation(nil)
      self.previewStatus.isHidden = false
    }
    if immediately { show() }
    else {
      let work = DispatchWorkItem(block: show)
      previewStatusWork = work
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }
  }

  func finishPreviewLoading(error: Bool = false) {
    previewStatusWork?.cancel()
    previewStatusWork = nil
    previewStatus.spinner.stopAnimation(nil)
    if error {
      preparePreviewStatus()
      previewStatus.message.stringValue = "Не удалось отобразить заметку"
      previewStatus.detail.stringValue = "Повторите загрузку текста и формул. Исходная заметка сохранена в редакторе."
      previewStatus.retry.isHidden = false
      previewStatus.isHidden = false
    } else {
      previewStatus.isHidden = true
    }
  }

  func finishRenderedPreview(generation: Int, in webView: WKWebView) {
    // JS completion can precede WebKit's first painted frame. Keep the loading
    // view until WebKit has produced that frame, so a blank surface never flashes.
    guard !previewStatus.isHidden else {
      finishPreviewLoading()
      return
    }
    let configuration = WKSnapshotConfiguration()
    configuration.afterScreenUpdates = true
    webView.takeSnapshot(with: configuration) { [weak self] _, _ in
      guard let self = self, generation == self.previewRenderGeneration,
        self.preview === webView else { return }
      self.finishPreviewLoading()
    }
  }

  @objc func retryMarkdownPreview() {
    previewRecoveryAttempts = 0
    previewRenderGeneration += 1
    preview?.removeFromSuperview()
    preview = nil
    previewReady = false
    lastPreviewPayload = nil
    renderMarkdown()
  }
}
