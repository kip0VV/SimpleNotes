import Cocoa
import WebKit
import UniformTypeIdentifiers

struct PDFNoteSelection {
  let notes: [URL]
  var selectedIndex: Int
  var selectedURL: URL? { notes.indices.contains(selectedIndex) ? notes[selectedIndex] : nil }
  init(notes: [URL], preferred: URL?) {
    self.notes = notes
    selectedIndex = preferred.flatMap { notes.firstIndex(of: $0) } ?? (notes.isEmpty ? -1 : 0)
  }
  func export(using generate: (URL) throws -> Void) throws {
    guard let url = selectedURL else { throw CocoaError(.fileReadNoSuchFile) }
    try generate(url)
  }
}

/// Uses the same bundled Markdown, math and color plugins as the note preview.
/// An isolated renderer keeps export independent of the open note and its theme.
final class NotePDFExporter: NSObject, WKNavigationDelegate {
  private(set) var webView: WKWebView?
  private var destination: URL?
  private var completion: ((Result<URL, Error>) -> Void)?
  private var timeout: Timer?


  static func html(note: NoteVersion, resources: URL) throws -> String {
    func resource(_ name: String) throws -> String {
      try String(contentsOf: resources.appendingPathComponent(name), encoding: .utf8)
    }
    let payload = try JSONSerialization.data(withJSONObject: [note.title, note.body])
    let json = String(decoding: payload, as: UTF8.self).replacingOccurrences(of: "<", with: "\\u003c")
    return """
      <!doctype html><html><head><meta charset="utf-8">
      <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval'; style-src 'unsafe-inline'; font-src data:">
      <style>
      \(try resource("katex.css"))
      \(try resource("note-colors.css"))
      :root{color-scheme:light;--note-accent:#245c9c}body{font:12pt -apple-system,sans-serif;line-height:1.5;color:#111;background:white;overflow-wrap:anywhere}
      h1,h2,h3{line-height:1.25;break-after:avoid}h1{font-size:24pt}h2{font-size:19pt}h3{font-size:15pt}
      pre{white-space:pre-wrap;padding:12px;background:#f3f3f3;border-radius:4px}code{font:10pt ui-monospace,monospace}
      blockquote{border-left:3px solid #999;margin-left:0;padding-left:12px;color:#555}
      table{border-collapse:collapse;width:100%}th,td{border:1px solid #999;padding:6px;text-align:left}
      tr{break-inside:avoid}thead{display:table-header-group}a{color:#245c9c}img{max-width:100%}
      .katex{font-size:1.1em}.katex-display{overflow-wrap:normal}.task-item{list-style:none}.task-mark{margin-left:-1.3em;margin-right:.4em}
      @page{size:A4;margin:18mm} @media print{body{margin:0;-webkit-print-color-adjust:exact}pre,blockquote{box-decoration-break:clone}}
      </style></head><body><h1 id="title"></h1><main id="body"></main>
      <script>\(try resource("markdown-it.min.js"))
      \(try resource("katex.js"))
      \(try resource("markdown-math.js"))
      \(try resource("note-colors.js"))
      const note=\(json);
      document.getElementById('title').textContent=note[0];
      document.documentElement.dataset.noteTheme='light';
      const parser=markdownit({html:false,linkify:true,breaks:true}).use(noteMath).use(noteColors);
      const tokens=parser.parse(note[1],{});
      for(let i=0;i<tokens.length;i++){
        if(tokens[i].type!=='list_item_open')continue;
        const inline=tokens[i+2],first=inline&&inline.children&&inline.children[0];
        if(!first||first.type!=='text')continue;
        const match=inline.content.match(/^\\[([ xX])\\](?:\\s+|$)/);
        if(!match)continue;
        first.content=first.content.slice(match[0].length);
        inline.children.unshift({type:'html_inline',content:'<span class="task-mark">'+(match[1].toLowerCase()==='x'?'☑':'☐')+'</span>'});
        tokens[i].attrJoin('class','task-item');
      }
      document.getElementById('body').innerHTML=parser.renderer.render(tokens,parser.options,{});
      </script></body></html>
      """
  }

  func export(note: NoteVersion, to url: URL, resources: URL,
    completion: @escaping (Result<URL, Error>) -> Void) {
    guard self.completion == nil else {
      completion(.failure(NSError(domain: "SimpleNotes.PDF", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Дождись завершения экспорта."])))
      return
    }
    self.completion = completion
    destination = url
    do {
      let html = try Self.html(note: note, resources: resources)
      let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 680, height: 900))
      view.navigationDelegate = self
      webView = view
      timeout = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
        self?.finish(.failure(NSError(domain: "SimpleNotes.PDF", code: 2,
          userInfo: [NSLocalizedDescriptionKey: "Превышено время ожидания экспорта PDF."])))
      }
      view.loadHTMLString(html, baseURL: nil)
    } catch { finish(.failure(error)) }
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    // Native PDF capture is asynchronous. Compute page cuts between text lines,
    // then compose A4 pages with vector content and consistent margins.
    let layout = """
      await document.fonts.ready;
      const width=680, maxHeight=(841.89-102)/(595.28-102)*width;
      const spans=[];
      const walker=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT);
      while(walker.nextNode()){
        if(!walker.currentNode.textContent.trim())continue;
        const range=document.createRange();range.selectNodeContents(walker.currentNode);
        for(const r of range.getClientRects())if(r.height>0&&r.height<maxHeight)spans.push([r.top+scrollY,r.bottom+scrollY]);
      }
      document.querySelectorAll('tr,pre,.katex-display').forEach(el=>{
        const r=el.getBoundingClientRect();if(r.height<maxHeight)spans.push([r.top+scrollY,r.bottom+scrollY]);
      });
      const total=Math.max(document.body.scrollHeight,document.documentElement.scrollHeight);
      const cuts=[0];let start=0;
      while(start<total){
        let end=Math.min(start+maxHeight,total);
        for(let pass=0;pass<spans.length;pass++){
          const crossing=spans.filter(r=>r[0]<end&&r[1]>end&&r[0]>start);
          if(!crossing.length)break;
          end=Math.min(...crossing.map(r=>r[0]));
        }
        if(end<=start+1)end=Math.min(start+maxHeight,total);
        cuts.push(end);start=end;
      }
      return cuts;
      """
    webView.callAsyncJavaScript(layout, arguments: [:], in: nil, in: .page) { [weak self] result in
      guard let self = self, self.completion != nil else { return }
      switch result {
      case .failure(let error): self.finish(.failure(error))
      case .success(let value):
        guard let cuts = value as? [Double], cuts.count >= 2 else {
          self.finish(.failure(CocoaError(.fileReadCorruptFile))); return
        }
        self.capturePages(cuts, in: webView)
      }
    }
  }

  private func capturePages(_ cuts: [Double], in view: WKWebView) {
    let output = NSMutableData()
    var mediaBox = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
    guard let consumer = CGDataConsumer(data: output as CFMutableData),
      let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
      finish(.failure(CocoaError(.fileWriteUnknown))); return
    }
    func capture(_ index: Int) {
      guard completion != nil else { context.closePDF(); return }
      guard index + 1 < cuts.count else {
        context.closePDF()
        do {
          guard let destination = destination else { throw CocoaError(.fileWriteUnknown) }
          try (output as Data).write(to: destination, options: .atomic)
          finish(.success(destination))
        } catch { finish(.failure(error)) }
        return
      }
      let height = cuts[index + 1] - cuts[index]
      let configuration = WKPDFConfiguration()
      configuration.rect = CGRect(x: 0, y: cuts[index], width: 680, height: height)
      view.createPDF(configuration: configuration) { [weak self] result in
        guard let self = self, self.completion != nil else { context.closePDF(); return }
        do {
          let data = try result.get()
          guard let provider = CGDataProvider(data: data as CFData),
            let document = CGPDFDocument(provider), let page = document.page(at: 1) else {
            throw CocoaError(.fileReadCorruptFile)
          }
          let scale = (mediaBox.width - 102) / 680
          let target = CGRect(x: 51, y: mediaBox.height - 51 - height * scale,
            width: mediaBox.width - 102, height: height * scale)
          context.beginPDFPage(nil)
          context.saveGState()
          context.concatenate(page.getDrawingTransform(.mediaBox, rect: target, rotate: 0, preserveAspectRatio: true))
          context.drawPDFPage(page)
          context.restoreGState()
          context.endPDFPage()
          capture(index + 1)
        } catch {
          context.closePDF()
          self.finish(.failure(error))
        }
      }
    }
    capture(0)
  }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { finish(.failure(CocoaError(.fileReadUnknown))) }
  private func finish(_ result: Result<URL, Error>) {
    guard let callback = completion else { return }
    completion = nil
    timeout?.invalidate(); timeout = nil
    webView?.stopLoading(); webView?.navigationDelegate = nil
    webView = nil
    destination = nil
    callback(result)
  }
}
