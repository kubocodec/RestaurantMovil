package com.wasi.restaurante

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.lang.reflect.InvocationTargetException
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    /// Un solo hilo: dos comandas simultáneas a la misma impresora se
    /// encolan en vez de pelear por el canal RFCOMM.
    private val hiloBluetooth = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CANAL_BLUETOOTH)
            .setMethodCallHandler { call, result ->
                if (call.method != "imprimir") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val mac = call.argument<String>("mac")
                val bytes = call.argument<ByteArray>("bytes")
                if (mac == null || bytes == null) {
                    result.error(ERROR_CONFIG, "Faltan la MAC o los datos a imprimir", null)
                    return@setMethodCallHandler
                }
                hiloBluetooth.execute {
                    try {
                        imprimirPorBluetooth(mac, bytes)
                        runOnUiThread { result.success(null) }
                    } catch (e: ErrorConfiguracion) {
                        runOnUiThread { result.error(ERROR_CONFIG, e.message, null) }
                    } catch (e: Exception) {
                        Log.w(TAG, "Fallo al imprimir en $mac", e)
                        runOnUiThread { result.error(ERROR_CONEXION, mensaje(e), null) }
                    }
                }
            }
    }

    /// Conecta, envía el ticket y cierra el socket siempre. A diferencia del
    /// plugin print_bluetooth_thermal, no exige BLUETOOTH_SCAN para conectar,
    /// prueba varios tipos de socket y devuelve el error real.
    private fun imprimirPorBluetooth(mac: String, bytes: ByteArray) {
        val adapter = (getSystemService(BLUETOOTH_SERVICE) as BluetoothManager?)?.adapter
            ?: throw ErrorConfiguracion("Este dispositivo no tiene Bluetooth")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            !tienePermiso(Manifest.permission.BLUETOOTH_CONNECT)
        ) {
            throw ErrorConfiguracion(
                "Falta el permiso de Dispositivos cercanos. Activalo en Ajustes > Apps > Wasi > Permisos"
            )
        }
        if (!adapter.isEnabled) throw ErrorConfiguracion("El Bluetooth del dispositivo esta apagado")
        if (!BluetoothAdapter.checkBluetoothAddress(mac)) {
            throw ErrorConfiguracion("La MAC \"$mac\" no tiene formato valido")
        }

        val device = adapter.getRemoteDevice(mac)
        // Una búsqueda de dispositivos en curso vuelve lenta o hace fallar la
        // conexión; cancelarla exige BLUETOOTH_SCAN, así que es opcional.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            tienePermiso(Manifest.permission.BLUETOOTH_SCAN)
        ) {
            try {
                adapter.cancelDiscovery()
            } catch (ignorada: SecurityException) {
            }
        }

        val socket = conectar(device)
        try {
            // La impresora descarta los primeros bytes si se escribe apenas
            // acepta la conexión (el ticket sale sin cabecera).
            Thread.sleep(400)
            socket.outputStream.apply {
                write(bytes)
                flush()
            }
            // Cerrar de inmediato deja el ticket impreso a la mitad: esperar a
            // que la impresora vacíe su búfer, proporcional al tamaño.
            Thread.sleep(minOf(300L + bytes.size / 4, 2500L))
        } finally {
            cerrar(socket)
        }
    }

    /// Prueba, en orden, el socket seguro (estándar), el inseguro y el canal
    /// RFCOMM 1 por reflexión: muchas térmicas genéricas rechazan el primero
    /// con "read failed, socket might closed" aunque estén emparejadas.
    private fun conectar(device: BluetoothDevice): BluetoothSocket {
        val intentos = listOf<Pair<String, () -> BluetoothSocket>>(
            "segura" to { device.createRfcommSocketToServiceRecord(UUID_SPP) },
            "insegura" to { device.createInsecureRfcommSocketToServiceRecord(UUID_SPP) },
            "canal 1" to {
                device.javaClass
                    .getMethod("createRfcommSocket", Int::class.javaPrimitiveType)
                    .invoke(device, 1) as BluetoothSocket
            },
        )
        val errores = mutableListOf<String>()
        for ((nombre, crear) in intentos) {
            var socket: BluetoothSocket? = null
            try {
                socket = crear()
                socket.connect()
                Log.i(TAG, "Conectado a ${device.address} por conexion $nombre")
                return socket
            } catch (e: Exception) {
                errores += "$nombre: ${mensaje(e)}"
                // Un socket fallido que no se cierra deja el canal tomado y
                // hace fallar también los intentos siguientes.
                socket?.let { cerrar(it) }
                Thread.sleep(300)
            }
        }
        val emparejada = device.bondState == BluetoothDevice.BOND_BONDED
        throw IOException(
            (if (emparejada) "" else "La impresora no esta emparejada con este telefono. ") +
                "No acepto la conexion (${errores.joinToString("; ")})"
        )
    }

    private fun cerrar(socket: BluetoothSocket) {
        try {
            socket.close()
        } catch (ignorada: IOException) {
        }
    }

    private fun tienePermiso(permiso: String) =
        checkSelfPermission(permiso) == PackageManager.PERMISSION_GRANTED

    /// La reflexión envuelve el error real en InvocationTargetException sin mensaje.
    private fun mensaje(e: Throwable): String {
        val real = if (e is InvocationTargetException) e.targetException ?: e else e
        return real.message ?: real.javaClass.simpleName
    }

    /// Errores que reintentar no arregla (Bluetooth apagado, sin permiso...).
    private class ErrorConfiguracion(mensaje: String) : Exception(mensaje)

    override fun onDestroy() {
        hiloBluetooth.shutdown()
        super.onDestroy()
    }

    companion object {
        private const val TAG = "WasiBluetooth"
        private const val CANAL_BLUETOOTH = "com.wasi.restaurante/bluetooth"
        private const val ERROR_CONFIG = "BT_CONFIG"
        private const val ERROR_CONEXION = "BT_CONEXION"
        private val UUID_SPP: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    }
}
