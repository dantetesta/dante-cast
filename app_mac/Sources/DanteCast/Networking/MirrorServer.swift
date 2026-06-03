import Foundation
import Network

/// Servidor TCP (Mac é o SERVIDOR; Android é o CLIENTE) baseado em Network.framework.
///
/// Responsabilidades:
///  - NWListener na porta configurada; aceita UMA conexão por vez.
///  - Lê o stream, reagrupa mensagens DCWP (length-prefixed) via MessageReader.
///  - Valida o token do HELLO; responde HELLO_ACK.
///  - Roteia VIDEO_CONFIG/VIDEO_FRAME ao decoder (via callbacks).
///  - Responde PING -> PONG (eco) para medição de latência.
///  - Publica status/erros no main actor (via callbacks @MainActor no AppState).
final class MirrorServer {

    // MARK: - Callbacks (consumidos pelo AppState; sempre disparados em main actor)

    var onStatusChange: ((ConnectionStatus) -> Void)?
    var onError: ((String) -> Void)?
    var onHello: ((Hello) -> Void)?                   // device conectado e validado
    var onVideoConfig: ((VideoConfigPayload) -> Void)?
    var onVideoFrame: ((VideoFramePayload) -> Void)?
    var onOrientation: ((Orientation) -> Void)?
    var onPingRoundTrip: ((Double) -> Void)?          // latência em ms (estimada via PONG)
    var onClientDisconnected: (() -> Void)?

    // MARK: - Estado interno

    private var listener: NWListener?
    private var connection: NWConnection?
    private let reader = MessageReader()
    private let queue = DispatchQueue(label: "com.dantetesta.dantecast.server")

    private var expectedToken: String = ""
    private var handshakeDone = false

    // Pareamento da sessão atual (preenchidos pelo AppState ao iniciar).
    var macName: String = NetworkInterfaces.hostName()
    var sessionId: String = UUID().uuidString
    var ackSettings: HelloAck.AckSettings = .init(width: 0, height: 0, fps: 30,
                                                  bitrate: 6_000_000, codec: "h264")

    // Para latência: guarda o instante de envio dos PINGs por nonce.
    private var pingTimestamps: [Int64: Date] = [:]
    private var pingTimer: DispatchSourceTimer?

    // MARK: - Ciclo de vida

    /// Inicia o listener na porta dada, validando conexões pelo `token`.
    func start(port: UInt16, token: String) {
        stop() // garante estado limpo

        self.expectedToken = token
        self.handshakeDone = false

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // Desabilita Nagle para reduzir latência de frames pequenos.
        if let tcpOpts = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            _ = tcpOpts
        }
        if let tcp = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.noDelay = true
        }

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            emitError("Porta inválida: \(port)")
            return
        }

        do {
            let l = try NWListener(using: params, on: nwPort)
            self.listener = l

            l.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    Log.net.info("Listener pronto na porta \(port)")
                    self.emitStatus(.listening)
                case .failed(let err):
                    Log.net.error("Listener falhou: \(err.localizedDescription)")
                    self.emitError("Falha no servidor: \(err.localizedDescription)")
                case .cancelled:
                    Log.net.info("Listener cancelado")
                default:
                    break
                }
            }

            l.newConnectionHandler = { [weak self] conn in
                guard let self = self else { return }
                // Aceita apenas uma conexão; recusa adicionais.
                if self.connection != nil {
                    Log.net.info("Conexão extra recusada")
                    conn.cancel()
                    return
                }
                self.accept(conn)
            }

            l.start(queue: queue)
        } catch {
            emitError("Não foi possível abrir a porta \(port): \(error.localizedDescription)")
        }
    }

    /// Para o servidor e fecha qualquer conexão ativa.
    func stop() {
        pingTimer?.cancel(); pingTimer = nil
        connection?.cancel(); connection = nil
        listener?.cancel(); listener = nil
        reader.reset()
        handshakeDone = false
        pingTimestamps.removeAll()
    }

    /// Envia STREAM_STOP + BYE e encerra a conexão graciosamente.
    func disconnectClient() {
        send(.init(type: .streamStop))
        send(.init(type: .bye))
        queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.connection?.cancel()
        }
    }

    // MARK: - Conexão

    private func accept(_ conn: NWConnection) {
        self.connection = conn
        self.reader.reset()
        self.handshakeDone = false
        emitStatus(.connecting)

        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                Log.net.info("Conexão estabelecida")
                self.receiveLoop(on: conn)
            case .failed(let err):
                Log.net.error("Conexão falhou: \(err.localizedDescription)")
                self.handleDisconnect()
            case .cancelled:
                self.handleDisconnect()
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    private func handleDisconnect() {
        pingTimer?.cancel(); pingTimer = nil
        if connection != nil {
            connection = nil
            reader.reset()
            handshakeDone = false
            pingTimestamps.removeAll()
            emitStatus(.disconnected)
            dispatchMain { self.onClientDisconnected?() }
            // Volta a escutar para um novo pareamento se o listener ainda existir.
            if listener != nil {
                emitStatus(.listening)
            }
        }
    }

    // Loop de recepção contínuo.
    private func receiveLoop(on conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) {
            [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, !data.isEmpty {
                self.reader.append(data)
                do {
                    let messages = try self.reader.drain()
                    for msg in messages { self.handle(msg) }
                } catch {
                    self.emitError("Protocolo inválido: \(error)")
                    conn.cancel()
                    return
                }
            }

            if let error = error {
                Log.net.error("Erro de recepção: \(error.localizedDescription)")
                self.handleDisconnect()
                return
            }
            if isComplete {
                self.handleDisconnect()
                return
            }
            // Continua recebendo.
            self.receiveLoop(on: conn)
        }
    }

    // MARK: - Roteamento de mensagens

    private func handle(_ msg: DCWP.Message) {
        switch msg.type {
        case .hello:
            handleHello(msg.payload)

        case .videoConfig:
            guard handshakeDone, let cfg = VideoConfigPayload.decode(msg.payload) else { return }
            dispatchMain { self.onVideoConfig?(cfg) }

        case .videoFrame:
            guard handshakeDone, let frame = VideoFramePayload.decode(msg.payload) else { return }
            if !streamingNotified {
                streamingNotified = true
                emitStatus(.streaming)
            }
            dispatchMain { self.onVideoFrame?(frame) }

        case .orientation:
            guard let o = try? JSONDecoder().decode(Orientation.self, from: msg.payload) else { return }
            dispatchMain { self.onOrientation?(o) }

        case .ping:
            // Eco imediato como PONG (o Android mede a latência).
            send(.init(type: .pong, payload: msg.payload))

        case .pong:
            handlePong(msg.payload)

        case .streamStop:
            streamingNotified = false
            emitStatus(.listening)

        case .bye:
            disconnectClient()

        case .error:
            if let e = try? JSONDecoder().decode(ErrorMsg.self, from: msg.payload) {
                emitError("Erro do dispositivo [\(e.code)]: \(e.message)")
            }

        case .helloAck:
            break // M→A only; ignorar se vier do cliente
        }
    }

    private var streamingNotified = false

    private func handleHello(_ payload: Data) {
        guard let hello = try? JSONDecoder().decode(Hello.self, from: payload) else {
            sendError(code: "BAD_HELLO", message: "HELLO malformado")
            connection?.cancel()
            return
        }

        // Valida versão e token.
        guard hello.protocolVersion == 1 else {
            sendHelloAck(accepted: false, reason: "Versão de protocolo incompatível")
            connection?.cancel()
            return
        }
        guard hello.token == expectedToken, !expectedToken.isEmpty else {
            Log.net.error("Token inválido recebido")
            sendHelloAck(accepted: false, reason: "Token inválido")
            queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.connection?.cancel() }
            return
        }

        handshakeDone = true
        streamingNotified = false
        sendHelloAck(accepted: true, reason: "")
        dispatchMain { self.onHello?(hello) }
        startPingTimer()
    }

    private func handlePong(_ payload: Data) {
        guard payload.count >= 8 else { return }
        let nonce = payload.readBE(Int64.self, at: payload.startIndex)
        guard let sent = pingTimestamps.removeValue(forKey: nonce) else { return }
        let rttMs = Date().timeIntervalSince(sent) * 1000.0
        dispatchMain { self.onPingRoundTrip?(rttMs) }
    }

    // MARK: - Envio

    private func send(_ message: DCWP.Message) {
        guard let conn = connection else { return }
        conn.send(content: message.encoded(), completion: .contentProcessed { error in
            if let error = error {
                Log.net.error("Erro ao enviar \(String(describing: message.type)): \(error.localizedDescription)")
            }
        })
    }

    private func sendHelloAck(accepted: Bool, reason: String) {
        let ack = HelloAck(accepted: accepted,
                           reason: reason,
                           macName: macName,
                           sessionId: sessionId,
                           settings: ackSettings)
        send(DCWP.helloAck(ack))
    }

    private func sendError(code: String, message: String) {
        send(DCWP.errorMsg(ErrorMsg(code: code, message: message)))
    }

    // MARK: - PING periódico (~2s) para medir latência

    private func startPingTimer() {
        pingTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.connection != nil else { return }
            let nonce = Int64(DispatchTime.now().uptimeNanoseconds)
            self.pingTimestamps[nonce] = Date()
            var p = Data(); p.appendBE(nonce)
            self.send(.init(type: .ping, payload: p))
            // Limpa pings sem resposta antigos (>10s).
            let cutoff = Date().addingTimeInterval(-10)
            self.pingTimestamps = self.pingTimestamps.filter { $0.value > cutoff }
        }
        timer.resume()
        pingTimer = timer
    }

    // MARK: - Helpers de despacho no main

    private func emitStatus(_ status: ConnectionStatus) {
        dispatchMain { self.onStatusChange?(status) }
    }
    private func emitError(_ message: String) {
        dispatchMain {
            self.onError?(message)
            self.onStatusChange?(.error)
        }
    }
    private func dispatchMain(_ block: @escaping () -> Void) {
        DispatchQueue.main.async(execute: block)
    }
}
