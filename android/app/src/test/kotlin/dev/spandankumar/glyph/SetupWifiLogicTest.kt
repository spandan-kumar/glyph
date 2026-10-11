package dev.spandankumar.glyph

import org.junit.Assert.*
import org.junit.Test

class SetupWifiLogicTest {
    @Test fun queuedCallbacksCannotBindAfterReleaseOrReplacement() {
        val requests = SetupWifiRequest()
        val first = Any(); val second = Any()
        var bound: Any? = null
        requests.active = first
        requests.active = null
        requests.run(first) { bound = first }
        assertNull(bound)
        requests.active = second
        requests.run(first) { bound = first }
        assertNull(bound)
        requests.run(second) { bound = second }
        assertSame(second, bound)
        requests.run(first) { bound = null }
        assertSame(second, bound)
    }

    @Test fun parsesDefaultsAndOverrides() {
        val d = SetupWifiLogic.parse(null)
        assertNull(d.ssid); assertEquals("WLED", d.prefix); assertEquals("wled1234", d.password)
        val a = SetupWifiLogic.parse(mapOf("ssid" to "Mine", "prefix" to "X", "password" to ""))
        assertEquals("Mine", a.ssid); assertEquals("X", a.prefix); assertEquals("", a.password)
        assertNull(SetupWifiLogic.parse(mapOf("ssid" to "")).ssid)
    }
    @Test fun labelStripsQuotesAndFallsBack() {
        val pat = SetupWifiLogic.parse(null)
        assertEquals("WLED-AP", SetupWifiLogic.label("\"WLED-AP\"", pat))
        assertEquals("WLED", SetupWifiLogic.label("<unknown ssid>", pat))
        assertEquals("WLED", SetupWifiLogic.label(null, pat))
        assertEquals("Mine", SetupWifiLogic.label("", SetupWifiLogic.parse(mapOf("ssid" to "Mine"))))
    }
    @Test fun supportStartsAtApi29() {
        assertFalse(SetupWifiLogic.supported(28)); assertTrue(SetupWifiLogic.supported(29))
        assertEquals("unavailable", SetupWifiLogic.unavailableCode())
    }
}
