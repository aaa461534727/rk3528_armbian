package com.playport.server

import org.slf4j.LoggerFactory

data class WifiNetwork(val ssid: String, val channel: Int)

/**
 * Reads the current Wi-Fi network so the wireless bootstrap can hand it to the phone.
 *
 * macOS: networksetup / ipconfig / system_profiler.
 * Linux: NetworkManager (nmcli) then iw, falling back to /proc/net/wireless.
 */
object WifiInfo {
    private val log = LoggerFactory.getLogger("wifi")

    fun detect(config: ServerConfig): WifiNetwork? {
        val ssid = config.wifiSsid?.takeIf { it.isNotBlank() } ?: currentSsid()
        if (ssid.isNullOrBlank()) return null
        val channel = if (config.wifiChannel > 0) config.wifiChannel else currentChannel() ?: 0
        return WifiNetwork(ssid, channel)
    }

    private val isLinux = System.getProperty("os.name").lowercase().contains("linux")

    private fun currentSsid(): String? = if (isLinux) linuxSsid() else macSsid()

    private fun currentChannel(): Int? = if (isLinux) linuxChannel() else macChannel()

    // --- Linux -------------------------------------------------------------

    private fun wirelessInterface(): String? {
        val iw = runCatching { run("iw", "dev") }.getOrNull() ?: return null
        return Regex("Interface\\s+(\\S+)").find(iw)?.groupValues?.get(1)
    }

    private fun linuxSsid(): String? {
        val nm = runCatching { run("nmcli", "-t", "-f", "ACTIVE,SSID", "device", "wifi") }.getOrNull()
        if (nm != null) {
            nm.lineSequence()
                .firstOrNull { it.startsWith("yes:") }
                ?.substringAfter(':')
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
                ?.let { return it }
        }
        val iface = wirelessInterface() ?: return null
        val link = runCatching { run("iw", "dev", iface, "link") }.getOrNull() ?: return null
        return Regex("SSID:\\s*(.+)").find(link)?.groupValues?.get(1)?.trim()?.takeIf { it.isNotEmpty() }
    }

    private fun linuxChannel(): Int? {
        val iface = wirelessInterface() ?: return null
        val link = runCatching { run("iw", "dev", iface, "link") }.getOrNull() ?: return null
        val freq = Regex("freq:\\s*(\\d+)").find(link)?.groupValues?.get(1)?.toIntOrNull() ?: return null
        return freqToChannel(freq)
    }

    private fun freqToChannel(freq: Int): Int = when {
        freq == 2484 -> 14
        freq in 2412..2472 -> (freq - 2407) / 5
        freq in 5000..5900 -> (freq - 5000) / 5
        freq in 5955..7115 -> (freq - 5950) / 5
        else -> 0
    }

    // --- macOS -------------------------------------------------------------

    private fun macSsid(): String? {
        wifiHardwarePort()?.let { device ->
            val output = runCatching { run("networksetup", "-getairportnetwork", device) }.getOrNull()
            output?.lineSequence()
                ?.firstOrNull { it.startsWith("Current Wi-Fi Network:") }
                ?.substringAfter(':')
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
                ?.let { return it }
        }
        for (iface in interfaceNames()) {
            val summary = runCatching { run("ipconfig", "getsummary", iface) }.getOrNull() ?: continue
            val ssid = summary.lineSequence()
                .firstOrNull { it.trim().startsWith("SSID :") }
                ?.substringAfter(':')
                ?.trim()
                ?: continue
            when {
                ssid.isEmpty() -> continue
                ssid == "<redacted>" -> {
                    log.warn(
                        "macOS hides the Wi-Fi name from this process (Location Services). " +
                            "Grant Location Services to your terminal, or pass --wifi-ssid and --wifi-passphrase.",
                    )
                    return null
                }
                else -> return ssid
            }
        }
        return null
    }

    private fun wifiHardwarePort(): String? = runCatching {
        val lines = run("networksetup", "-listallhardwareports").lines()
        val index = lines.indexOfFirst { it.trim().equals("Hardware Port: Wi-Fi", ignoreCase = true) }
        if (index >= 0 && index + 1 < lines.size) lines[index + 1].substringAfter(':').trim() else null
    }.getOrNull()

    private fun interfaceNames(): List<String> = runCatching {
        java.net.NetworkInterface.getNetworkInterfaces().toList().map { it.name }
    }.getOrDefault(emptyList())

    private fun macChannel(): Int? = runCatching {
        val output = run("system_profiler", "SPAirPortDataType")
        Regex("Channel:\\s*(\\d+)").find(output)?.groupValues?.get(1)?.toIntOrNull()
    }.getOrNull()

    private fun run(vararg command: String): String {
        val process = ProcessBuilder(*command).redirectErrorStream(true).start()
        val output = process.inputStream.bufferedReader().readText()
        process.waitFor()
        return output
    }
}
