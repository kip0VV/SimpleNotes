import Cocoa
import WebKit

extension NotesApp {
  func renderMarkdown() {
    guard let script = markdownScript,
      let katexURL = Bundle.main.url(forResource: "katex", withExtension: "js"),
      let mathURL = Bundle.main.url(forResource: "markdown-math", withExtension: "js"),
      let cssURL = Bundle.main.url(forResource: "katex", withExtension: "css"),
      let katex = try? String(contentsOf: katexURL, encoding: .utf8),
      let math = try? String(contentsOf: mathURL, encoding: .utf8),
      let mathCSS = try? String(contentsOf: cssURL, encoding: .utf8)
    else {
      showError("Не найден компонент предпросмотра Markdown.")
      return
    }
    if preview == nil {
      let configuration = WKWebViewConfiguration()
      configuration.userContentController.add(TaskToggleHandler(owner: self), name: "taskToggle")
      let webView = WKWebView(frame: .zero, configuration: configuration)
      webView.translatesAutoresizingMaskIntoConstraints = false
      webView.navigationDelegate = self
      webView.allowedTouchTypes = [.indirect]
      previewContainer.addSubview(webView)
      NSLayoutConstraint.activate([
        webView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
        webView.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
        webView.topAnchor.constraint(equalTo: previewContainer.topAnchor),
        webView.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),
      ])
      preview = webView
      webView.pageZoom = noteZoom
      let html = """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; font-src data:"><style>
        \(mathCSS)
        .katex-display{overflow-x:auto;overflow-y:hidden;padding:.25em 0}.katex{overflow-wrap:normal}.math-error{color:var(--note-accent);white-space:pre-wrap}
        body{font:16px -apple-system,BlinkMacSystemFont,sans-serif;line-height:1.65;margin:24px;overflow-wrap:anywhere}h1,h2,h3{line-height:1.25}h1{font-size:28px}h2{font-size:23px}h3{font-size:19px}pre{padding:16px;background:rgba(128,128,128,.15);border-radius:8px;overflow:auto}code{font-family:ui-monospace,monospace;font-size:.9em}blockquote{border-left:3px solid #888;margin-left:0;padding-left:16px;color:#888}table{border-collapse:collapse;display:block;overflow:auto}th,td{border:1px solid #888;padding:7px 12px}a{color:var(--note-accent,#609bff)}.task-item{list-style:none}.task-item input{margin-left:-1.4em;margin-right:.45em;accent-color:var(--note-accent,#ff575f);cursor:pointer}.date{color:#888;font-size:12px}hr{border:0;border-top:1px solid #888}
        </style></head><body><h1 id="title"></h1><div class="date" id="date"></div><main id="body"></main><script>\(script)
        \(katex)
        \(math)
        const parser=markdownit({html:false,linkify:true,breaks:true}).use(noteMath);
        window.renderNote=(note,theme,revision)=>{
          document.documentElement.style.colorScheme=theme;
          document.getElementById('title').textContent=note[1];
          document.getElementById('date').textContent=note[2];
          const tokens=parser.parse(note[0],{});
          for(let i=0;i<tokens.length;i++){
            if(tokens[i].type!=='list_item_open')continue;
            const inline=tokens[i+2];
            if(!inline||inline.type!=='inline'||!inline.children)continue;
            const first=inline.children[0];
            if(!first||first.type!=='text')continue;
            const match=inline.content.match(/^\\[([ xX])\\](?:\\s+|$)/);
            if(!match)continue;
            const line=tokens[i].map[0];
            first.content=first.content.slice(match[0].length);
            inline.children.unshift({type:'html_inline',content:'<input type="checkbox" data-line="'+line+'"'+(match[1].toLowerCase()==='x'?' checked':'')+'>'});
            tokens[i].attrJoin('class','task-item');
          }
          document.getElementById('body').innerHTML=parser.renderer.render(tokens,parser.options,{});
          document.querySelectorAll('input[data-line]').forEach(input=>{
            input.setAttribute('aria-label',input.parentElement.textContent.trim());
            input.addEventListener('change',()=>{
              window.webkit.messageHandlers.taskToggle.postMessage({line:Number(input.dataset.line),checked:input.checked,revision});
            });
          });
        };

        </script></body></html>
        """
      webView.loadHTMLString(html, baseURL: nil)
    }
    guard previewReady else { return }
    do {
      let data = try JSONSerialization.data(withJSONObject: [
        editor.string, titleField.stringValue,
        showDates ? noteDate : "",
      ])
      let json = String(decoding: data, as: UTF8.self).replacingOccurrences(
        of: "<", with: "\\u003c")
      let theme =
        (NSApp.appearance ?? window.effectiveAppearance).bestMatch(from: [.darkAqua, .aqua])
          == .darkAqua ? "dark" : "light"
      let styleValues: [String: Any] = [
        "accent": isGraphite ? "#9BCBE7" : "#609bff",
        "font": editorStyle?.fontName ?? "-apple-system",
        "size": editorStyle?.fontSize ?? 16,
        "background": editorBackgroundHex,
        "foreground": editorForegroundHex,
      ]
      let styleData = try JSONSerialization.data(withJSONObject: styleValues)
      let styleJSON = String(decoding: styleData, as: UTF8.self).replacingOccurrences(of: "<", with: "\\u003c")
      let contentKey = styleJSON + json + theme + (currentURL?.path ?? "draft")
      guard contentKey != lastPreviewPayload else { return }
      lastPreviewPayload = contentKey
      if !updatingTask || previewRevision.isEmpty { previewRevision = UUID().uuidString }
      let payload = "var s=\(styleJSON);document.documentElement.style.setProperty('--note-accent',s.accent);document.body.style.fontFamily=s.font;document.body.style.fontSize=s.size+'px';document.body.style.backgroundColor=s.background;document.body.style.color=s.foreground;window.renderNote(\(json), '\(theme)', '\(previewRevision)')"
      preview?.evaluateJavaScript(payload) { [weak self] _, error in
        if error != nil && self?.lastPreviewPayload == contentKey { self?.lastPreviewPayload = nil }
      }
    } catch { showError(error.localizedDescription) }
  }

  func webView(
    _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    guard let url = action.request.url else {
      decisionHandler(.allow)
      return
    }
    if url.absoluteString == "about:blank" {
      decisionHandler(.allow)
      return
    }
    if action.navigationType == .linkActivated,
      ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "")
    {
      NSWorkspace.shared.open(url)
    }
    decisionHandler(.cancel)
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    guard webView === preview else { return }
    previewReady = true
    renderMarkdown()
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    guard webView === preview else { return }
    webView.removeFromSuperview()
    preview = nil
    previewReady = false
    lastPreviewPayload = nil
    if mode.selectedSegment == 1 { renderMarkdown() }
  }
}
