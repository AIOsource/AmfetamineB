import Foundation
import Network
import UIKit

/// Lightweight local HTTP server using Network.framework to receive pairing plists
/// directly from the PC Helper application over USB/Wi-Fi.
final class PCHelperSync: ObservableObject {
    static let shared = PCHelperSync()

    @Published var isListening: Bool = false
    @Published var listeningPort: UInt16 = 8765
    @Published var statusMessage: String = "Ready for PC connection"
    @Published var lastReceivedFile: String? = nil

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.amfetaspoit.pchelper.sync", qos: .userInitiated)

    func start() {
        guard listener == nil else { return }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: listeningPort) ?? 8765)

            listener.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.isListening = true
                        self?.statusMessage = "Listening on port \(self?.listeningPort ?? 8765)"
                    case .failed(let error):
                        self?.isListening = false
                        self?.statusMessage = "Listener failed: \(error.localizedDescription)"
                    case .cancelled:
                        self?.isListening = false
                        self?.statusMessage = "Stopped"
                    default:
                        break
                    }
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener.start(queue: queue)
            self.listener = listener
        } catch {
            DispatchQueue.main.async {
                self.statusMessage = "Could not start server: \(error.localizedDescription)"
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        DispatchQueue.main.async {
            self.isListening = false
            self.statusMessage = "Stopped"
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveData(on: connection, accumulated: Data())
    }

    private func receiveData(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            var current = accumulated
            if let data = data {
                current.append(data)
            }

            if error != nil {
                connection.cancel()
                return
            }

            // Check if we have received a full HTTP request
            if let boundaryRange = current.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = current.subdata(in: 0..<boundaryRange.lowerBound)
                let headerString = String(data: headerData, encoding: .utf8) ?? ""
                let bodyData = current.subdata(in: boundaryRange.upperBound..<current.count)

                // Parse Content-Length if present
                var expectedLength: Int? = nil
                for line in headerString.components(separatedBy: "\r\n") {
                    if line.lowercased().hasPrefix("content-length:") {
                        let parts = line.components(separatedBy: ":")
                        if parts.count > 1, let len = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                            expectedLength = len
                        }
                    }
                }

                if let expected = expectedLength {
                    if bodyData.count >= expected {
                        self.processPayload(bodyData: Data(bodyData.prefix(expected)), connection: connection)
                        return
                    }
                } else if isComplete || bodyData.count > 0 {
                    self.processPayload(bodyData: bodyData, connection: connection)
                    return
                }
            }

            if isComplete {
                connection.cancel()
            } else {
                self.receiveData(on: connection, accumulated: current)
            }
        }
    }

    private func processPayload(bodyData: Data, connection: NWConnection) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let aircardURL = docs.appendingPathComponent("aircard_pairing.plist")
        let airliftURL = docs.appendingPathComponent("airlift_pairing.plist")

        var success = false
        if !bodyData.isEmpty {
            do {
                try bodyData.write(to: aircardURL, options: .atomic)
                try bodyData.write(to: airliftURL, options: .atomic)
                success = true
            } catch {
                success = false
            }
        }

        let responseBody = success ? "{\"status\":\"ok\",\"message\":\"Pairing file synced successfully!\"}" : "{\"status\":\"error\"}"
        let httpResponse = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: \(responseBody.utf8.count)\r\n\r\n\(responseBody)"

        connection.send(content: Data(httpResponse.utf8), completion: .contentProcessed({ _ in
            connection.cancel()
        }))

        if success {
            DispatchQueue.main.async {
                PairingController.customPairingFilePath = aircardURL.path
                AppViewModel.shared?.refreshPairingFile()
                AppViewModel.shared?.pairingStatus = "Pairing file synced from PC Helper! [OK]"
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            }
        }
    }
}
