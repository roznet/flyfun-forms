import SwiftUI
import WebKit

/// Opens an airport's official web form (book-out, PPR, out-of-hours…) and
/// prefills it from a fill plan. Nothing is sent from the app: the pilot
/// reviews the page and submits it on the airport's own site.
struct WebFormView: View {
    let plan: FillPlan
    @Environment(\.dismiss) private var dismiss
    @State private var status: WebFormStatus = .loading
    @State private var fillRequest = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                banner
                Divider()
                WebFormWebView(plan: plan, fillRequest: fillRequest) { status = $0 }
            }
            .navigationTitle(plan.label)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        fillRequest += 1
                    } label: {
                        Label("Fill Again", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 760)
        #endif
    }

    private var banner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Prefilled from your flight. Check every field, then tap Submit on the page — nothing is sent until you do.")
                .font(.caption)
            if let note = plan.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            statusLine
                .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch status {
        case .loading:
            Label("Loading form…", systemImage: "hourglass")
                .foregroundStyle(.secondary)
        case .filled(let count, let missing) where missing.isEmpty:
            Label("Filled \(count) fields", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case .filled(let count, let missing):
            Label("Filled \(count) fields, but \(missing.count) weren't found on the page — it may have changed, so fill those by hand.",
                  systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        case .failed(let message):
            Label(message, systemImage: "xmark.octagon")
                .foregroundStyle(.red)
        }
    }
}

enum WebFormStatus: Equatable {
    case loading
    case filled(count: Int, missing: [String])
    case failed(String)
}

/// Web view that loads the plan's page and fills it once loaded, and again
/// whenever `fillRequest` changes.
struct WebFormWebView {
    let plan: FillPlan
    let fillRequest: Int
    let onStatus: (WebFormStatus) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(plan: plan, onStatus: onStatus)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let plan: FillPlan
        var onStatus: (WebFormStatus) -> Void
        private var hasFilled = false
        private var lastFillRequest = 0
        private weak var webView: WKWebView?

        init(plan: FillPlan, onStatus: @escaping (WebFormStatus) -> Void) {
            self.plan = plan
            self.onStatus = onStatus
        }

        func makeWebView() -> WKWebView {
            let configuration = WKWebViewConfiguration()
            // Nothing from these pages needs to outlive the sheet
            configuration.websiteDataStore = .nonPersistent()
            let webView = WKWebView(frame: .zero, configuration: configuration)
            webView.navigationDelegate = self
            webView.load(URLRequest(url: plan.url))
            self.webView = webView
            return webView
        }

        func update(fillRequest: Int) {
            guard fillRequest != lastFillRequest else { return }
            lastFillRequest = fillRequest
            fill()
        }

        // Fill after the first load only: submitting a RedAtlas form loads a
        // confirmation page, which must not be filled again.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !hasFilled else { return }
            hasFilled = true
            fill()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onStatus(.failed(error.localizedDescription))
        }

        private func fill() {
            guard let webView,
                  let planData = try? JSONEncoder().encode(plan),
                  let planJSON = String(data: planData, encoding: .utf8) else { return }
            webView.evaluateJavaScript("(\(WebFormFiller.script))(\(planJSON))") { [weak self] result, error in
                guard let self else { return }
                if let error {
                    self.onStatus(.failed(error.localizedDescription))
                    return
                }
                guard let json = result as? String,
                      let outcome = try? JSONDecoder().decode(WebFormFiller.Outcome.self, from: Data(json.utf8)) else {
                    self.onStatus(.failed(String(localized: "Couldn't fill the form")))
                    return
                }
                self.onStatus(.filled(count: outcome.filled.count, missing: outcome.missing))
            }
        }
    }
}

#if os(iOS)
extension WebFormWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        context.coordinator.makeWebView()
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onStatus = onStatus
        context.coordinator.update(fillRequest: fillRequest)
    }
}
#else
extension WebFormWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        context.coordinator.makeWebView()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onStatus = onStatus
        context.coordinator.update(fillRequest: fillRequest)
    }
}
#endif

/// The script that applies a fill plan to the page. It is generic: all it
/// knows is "find the input with this name, give it this value", so a form
/// change on the airport's side is fixed in the server's mapping, not here.
enum WebFormFiller {
    struct Outcome: Decodable {
        var filled: [String]
        var missing: [String]
    }

    static let script = #"""
    function (plan) {
      const root = plan.scope ? document.querySelector(plan.scope) : document;
      if (!root) {
        return JSON.stringify({ filled: [], missing: plan.fields.map(f => f.name) });
      }
      const filled = [];
      const missing = [];
      for (const field of plan.fields) {
        const el = root.querySelector('[name="' + CSS.escape(field.name) + '"]');
        if (!el) {
          missing.push(field.name);
          continue;
        }
        if (field.type === "checkbox") {
          // Click rather than set, so the page's own handlers run (RedAtlas
          // enables its return fields from the checkbox's click handler).
          if (el.checked !== (field.value === "true")) { el.click(); }
        } else {
          // The prototype's setter, so pages that track input values see it
          const setter = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(el), "value")?.set;
          if (setter) { setter.call(el, field.value); } else { el.value = field.value; }
          // Date/time pickers (Elementor uses flatpickr) keep their own state
          if (el._flatpickr) { el._flatpickr.setDate(field.value, false); }
          // So does RedAtlas's autocomplete (autocomplete.js on jQuery)
          if (window.jQuery && window.jQuery(el).data("aaAutocomplete")) {
            window.jQuery(el).autocomplete("val", field.value);
          }
          el.dispatchEvent(new Event("input", { bubbles: true }));
          el.dispatchEvent(new Event("change", { bubbles: true }));
        }
        filled.push(field.name);
      }
      if (root !== document) { root.scrollIntoView({ behavior: "smooth", block: "start" }); }
      return JSON.stringify({ filled: filled, missing: missing });
    }
    """#
}
