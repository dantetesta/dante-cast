package com.dantetesta.dantecast.pairing

import android.annotation.SuppressLint
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import com.google.mlkit.vision.barcode.BarcodeScanner
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import kotlinx.serialization.json.Json

/**
 * Analisador de frames da CameraX que procura um QR Code e tenta interpretá-lo
 * como o JSON de pareamento [PairingQr].
 *
 * @param onResult chamado UMA vez quando um QR válido é encontrado (callback na main thread
 *        do executor configurado pela ImageAnalysis). Após o primeiro hit, ignora os demais.
 */
class QrAnalyzer(
    private val onResult: (PairingQr) -> Unit
) : ImageAnalysis.Analyzer {

    // JSON tolerante a chaves extras (compatibilidade futura do protocolo).
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    // Restringe ao formato QR para acelerar a detecção.
    private val scanner: BarcodeScanner = BarcodeScanning.getClient(
        BarcodeScannerOptions.Builder()
            .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
            .build()
    )

    // Evita disparar o callback várias vezes para o mesmo pareamento.
    @Volatile
    private var handled = false

    @SuppressLint("UnsafeOptInUsageError")
    override fun analyze(imageProxy: ImageProxy) {
        if (handled) {
            imageProxy.close()
            return
        }
        val mediaImage = imageProxy.image
        if (mediaImage == null) {
            imageProxy.close()
            return
        }

        val input = InputImage.fromMediaImage(
            mediaImage,
            imageProxy.imageInfo.rotationDegrees
        )

        scanner.process(input)
            .addOnSuccessListener { barcodes ->
                for (barcode in barcodes) {
                    val raw = barcode.rawValue ?: continue
                    val parsed = tryParse(raw)
                    if (parsed != null && !handled) {
                        handled = true
                        onResult(parsed)
                        break
                    }
                }
            }
            .addOnCompleteListener {
                // SEMPRE fechar o ImageProxy para liberar o buffer da câmera.
                imageProxy.close()
            }
    }

    /** Tenta desserializar o conteúdo do QR; valida campos mínimos. */
    private fun tryParse(raw: String): PairingQr? = runCatching {
        val qr = json.decodeFromString(PairingQr.serializer(), raw)
        if (qr.ip.isBlank() || qr.token.isBlank() || qr.port <= 0) null else qr
    }.getOrNull()

    /** Libera o scanner do ML Kit (chamar no onDispose da tela). */
    fun close() {
        runCatching { scanner.close() }
    }
}
