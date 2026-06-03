import SwiftUI

/// Tela inicial: apresenta o app e o passo a passo de uso.
struct WelcomeView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            VStack(spacing: 6) {
                Text("Dante Cast")
                    .font(.largeTitle.bold())
                Text("Espelhe a tela do seu Android no Mac, sem fio.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                stepRow(number: 1, text: "Clique em \"Iniciar e Parear\" para exibir o QR code.")
                stepRow(number: 2, text: "No app Android, escaneie o QR para conectar.")
                stepRow(number: 3, text: "A tela do Android aparece aqui em tempo real.")
            }
            .padding(20)
            .frame(maxWidth: 460, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))

            Button {
                app.startServer()
            } label: {
                Label("Iniciar e Parear", systemImage: "play.fill")
                    .frame(minWidth: 160)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.body)
            Spacer(minLength: 0)
        }
    }
}
