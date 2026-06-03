import SwiftUI

/// Ajuda e solução de problemas.
struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Ajuda e Solução de Problemas")
                    .font(.title2.bold())

                helpSection(
                    title: "Como conectar",
                    items: [
                        "Inicie o servidor na tela Início ou Parear.",
                        "No Android, abra o Dante Cast e escaneie o QR code.",
                        "Se a câmera não funcionar, digite IP, porta e código manualmente.",
                        "O Mac e o Android precisam estar na MESMA rede Wi-Fi."
                    ])

                helpSection(
                    title: "Não aparece imagem",
                    items: [
                        "Verifique se o status está \"Transmitindo\".",
                        "O stream só começa após um keyframe (pode levar 1-2s).",
                        "Confirme que o firewall do macOS permite o Dante Cast.",
                        "Tente reduzir a qualidade em Ajustes se houver travamentos."
                    ])

                helpSection(
                    title: "Latência alta",
                    items: [
                        "Use a rede 5GHz e fique próximo do roteador.",
                        "Reduza a resolução para 720p e o FPS para 30.",
                        "Evite redes corporativas com isolamento de clientes (AP isolation)."
                    ])

                helpSection(
                    title: "Porta ocupada / erro ao iniciar",
                    items: [
                        "Outra instância pode estar usando a porta 7843.",
                        "Altere a porta em Ajustes e reinicie o servidor."
                    ])

                helpSection(
                    title: "Gravações e capturas",
                    items: [
                        "Arquivos vão para a pasta definida em Ajustes (padrão: Filmes/DanteCast).",
                        "Capturas são PNG; gravações são .mov (H.264)."
                    ])
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
        }
    }

    private func helpSection(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.tint)
                        .font(.callout)
                    Text(item)
                        .font(.callout)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}
