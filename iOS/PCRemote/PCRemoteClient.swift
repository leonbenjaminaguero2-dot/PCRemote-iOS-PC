import Foundation
import UIKit

@MainActor
final class PCRemoteClient: ObservableObject {
    @Published var host = UserDefaults.standard.string(forKey: "pcremote.host") ?? "192.168.1.100"
    @Published var pin = UserDefaults.standard.string(forKey: "pcremote.pin") ?? ""
    @Published var connected = false
    @Published var statusText = "Sin conectar"
    @Published var latestFrame: UIImage?
    @Published var busy = false

    private var frameTask: Task<Void, Never>?
    private var baseURL: URL? {
        let clean = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        return URL(string: "http://\(clean):8765")
    }

    func saveSettings() {
        UserDefaults.standard.set(host, forKey: "pcremote.host")
        UserDefaults.standard.set(pin, forKey: "pcremote.pin")
    }

    private func request(path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> (Data, URLResponse) {
        guard let baseURL, let url = URL(string: path, relativeTo: baseURL) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 4
        request.setValue(pin, forHTTPHeaderField: "X-PCRemote-Pin")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return try await URLSession.shared.data(for: request)
    }

    func testConnection() async {
        saveSettings()
        do {
            let (data, response) = try await request(path: "/api/status")
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.userAuthenticationRequired) }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            statusText = "Conectado · \(json?["computer"] as? String ?? "PC")"
            connected = true
        } catch {
            connected = false
            statusText = "No se pudo conectar. Revisá IP, PIN y Wi‑Fi."
        }
    }

    func startPreview() {
        stopPreview()
        frameTask = Task {
            while !Task.isCancelled {
                do {
                    let (data, response) = try await request(path: "/api/screen.jpg")
                    if (response as? HTTPURLResponse)?.statusCode == 200, let image = UIImage(data: data) {
                        latestFrame = image
                        connected = true
                    }
                } catch {
                    connected = false
                }
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    func stopPreview() { frameTask?.cancel(); frameTask = nil }

    func action(_ name: String) async {
        do {
            _ = try await request(path: "/api/power", method: "POST", body: ["action": name])
            statusText = "Orden enviada: \(name)"
        } catch { statusText = "No se pudo enviar la orden." }
    }

    func sendKey(_ key: String) async {
        do { _ = try await request(path: "/api/input", method: "POST", body: ["type": "key", "key": key]) }
        catch { statusText = "No se pudo enviar el control." }
    }

    func sendMouse(x: Double, y: Double, button: String = "move") async {
        do { _ = try await request(path: "/api/input", method: "POST", body: ["type": "mouse", "x": x, "y": y, "button": button]) }
        catch { statusText = "No se pudo enviar el ratón." }
    }
}
