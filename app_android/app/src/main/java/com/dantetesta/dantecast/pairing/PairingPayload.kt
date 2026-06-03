package com.dantetesta.dantecast.pairing

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Modelos @Serializable do pareamento e do handshake DCWP v1.
 * As chaves JSON DEVEM bater byte-a-byte com o lado macOS (ver spec DCWP no README).
 */

/**
 * QR de pareamento exibido pelo Mac:
 * {"v":1,"ip":"<lan ip>","port":7843,"token":"<token>","name":"<mac name>"}
 */
@Serializable
data class PairingQr(
    val v: Int = 1,
    val ip: String,
    val port: Int = 7843,
    val token: String,
    val name: String = ""
)

/** Subobjeto "device" do HELLO. */
@Serializable
data class HelloDevice(
    val id: String,
    val name: String,
    val model: String,
    val osVersion: String
)

/** Subobjeto "capabilities" do HELLO. */
@Serializable
data class HelloCapabilities(
    val maxWidth: Int,
    val maxHeight: Int,
    val fpsOptions: List<Int> = listOf(30, 60)
)

/**
 * HELLO (A→M):
 * {"protocolVersion":1,"token":"...","device":{...},"capabilities":{...}}
 */
@Serializable
data class Hello(
    val protocolVersion: Int = 1,
    val token: String,
    val device: HelloDevice,
    val capabilities: HelloCapabilities
)

/** Subobjeto "settings" do HELLO_ACK — configurações oficiais decididas pelo Mac. */
@Serializable
data class AckSettings(
    val width: Int,
    val height: Int,
    val fps: Int,
    val bitrate: Int,
    val codec: String = "h264"
)

/**
 * HELLO_ACK (M→A):
 * {"accepted":true,"reason":"","macName":"...","sessionId":"...","settings":{...}}
 */
@Serializable
data class HelloAck(
    val accepted: Boolean,
    val reason: String = "",
    val macName: String = "",
    val sessionId: String = "",
    val settings: AckSettings? = null
)

/** ORIENTATION (A→M): {"width":int,"height":int,"rotation":0|90|180|270} */
@Serializable
data class Orientation(
    val width: Int,
    val height: Int,
    val rotation: Int
)

/** ERROR (qualquer direção): {"code":"","message":""} */
@Serializable
data class ProtocolError(
    val code: String = "",
    val message: String = ""
)
