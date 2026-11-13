import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// Share extension: saves shared email text to the App Group so Trippin can
/// pick it up next time it opens.
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareView(model: model) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        Task { await collect() }
    }

    private func collect() async {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        var pieces: [String] = []
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
               let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                pieces.append(text)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                      let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                pieces.append(url.absoluteString)
            }
        }
        let text = pieces.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        await MainActor.run {
            if text.isEmpty {
                model.state = .failed("There was no text to save. Copy the email and paste it in Trippin instead.")
            } else if !SharedInbox.isAvailable {
                model.state = .failed("Trippin couldn't save this. Copy the email and paste it in Trippin instead.")
            } else {
                SharedInbox.add(text)
                model.state = .saved
            }
        }
    }
}

final class ShareModel: ObservableObject {
    enum State { case loading, saved, failed(String) }
    @Published var state: State = .loading
}

private struct ShareView: View {
    @ObservedObject var model: ShareModel
    var done: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                switch model.state {
                case .loading:
                    ProgressView()
                case .saved:
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(.green)
                    Text("Saved to Trippin").font(.title3.bold())
                    Text("Open Trippin to review the reservation and add it to a trip.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                case .failed(let message):
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 48)).foregroundStyle(.orange)
                    Text(message).multilineTextAlignment(.center)
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done", action: done) }
            }
            .navigationTitle("Trippin")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
