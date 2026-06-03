import SwiftUI

/// Tela de pareamento: QR code + dados manuais (IP, porta, código).
struct PairDeviceView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Parear Dispositivo")
                    .font(.title2.bold())
                Spacer()
                StatusBadge(status: app.status)
            }

            if let pairing = app.pairing {
                pairedContent(pairing)
            } else {
                notRunningContent
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Servidor no ar (QR disponível)

    @ViewBuilder
    private func pairedContent(_ pairing: PairingService.PairingInfo) -> some View {
        VStack(spacing: 18) {
            Text("Escaneie com o app Dante Cast no Android")
                .font(.headline)
                .foregroundStyle(.secondary)

            if let qr = pairing.qrImage {
                Image(nsImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 260, height: 260)
                    .padding(14)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
            } else {
                ContentUnavailablePlaceholder(
                    icon: "qrcode",
                    title: "QR indisponível",
                    message: "Não foi possível gerar o QR code.")
            }

            // Dados manuais (caso a câmera não funcione).
            GroupBox("Conexão manual") {
                VStack(alignment: .leading, spacing: 8) {
                    manualRow(label: "IP", value: pairing.payload.ip)
                    manualRow(label: "Porta", value: String(pairing.payload.port))
                    manualRow(label: "Código", value: pairing.payload.token)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: 420)

            if pairing.payload.ip == "0.0.0.0" {
                Label("Conecte o Mac a uma rede Wi-Fi/Ethernet para obter um IP.",
                      systemImage: "wifi.exclamationmark")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 12) {
                Button(role: .destructive) {
                    app.stopServer()
                    app.screen = .welcome
                } label: {
                    Label("Parar Servidor", systemImage: "stop.fill")
                }
                Button {
                    app.startServer() // regenera token/QR
                } label: {
                    Label("Novo Código", systemImage: "arrow.clockwise")
                }
            }
            .controlSize(.large)
        }
    }

    private func manualRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(.callout.monospaced())
                .textSelection(.enabled)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copiar")
        }
    }

    // MARK: - Servidor parado

    private var notRunningContent: some View {
        VStack(spacing: 16) {
            ContentUnavailablePlaceholder(
                icon: "qrcode.viewfinder",
                title: "Servidor parado",
                message: "Inicie o servidor para gerar o QR de pareamento.")
            Button {
                app.startServer()
            } label: {
                Label("Iniciar e Parear", systemImage: "play.fill")
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Placeholder simples e reutilizável (substitui ContentUnavailableView p/ compat. ampla).
struct ContentUnavailablePlaceholder: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: 420)
    }
}
