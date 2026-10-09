package dev.glassp.ha_sidecar

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DashboardPathTest {
    @Test fun fullBrowserUrl() = assertEquals("lovelace/wall-panel", DashboardPath.normalize("https://home.glassp.dev/lovelace/wall-panel"))
    @Test fun urlWithPortAndTrailingSlash() = assertEquals("lovelace/wall-panel/", DashboardPath.normalize("http://192.168.1.5:8123/lovelace/wall-panel/"))
    @Test fun leadingSlashPath() = assertEquals("dashboard-kitchen/0", DashboardPath.normalize("/dashboard-kitchen/0"))
    @Test fun barePath() = assertEquals("lovelace/0", DashboardPath.normalize("lovelace/0"))
    @Test fun queryIsKept() = assertEquals("lovelace/wall?kiosk", DashboardPath.normalize("https://h/lovelace/wall?kiosk"))
    @Test fun fragmentIsDropped() = assertEquals("lovelace/wall", DashboardPath.normalize("https://h/lovelace/wall#top"))
    @Test fun surroundingWhitespace() = assertEquals("lovelace/wall", DashboardPath.normalize("  https://h/lovelace/wall \n"))
    @Test fun pastedDeepLink() = assertEquals("lovelace/default", DashboardPath.normalize("homeassistant://navigate/lovelace/default"))
    @Test fun blankClears() = assertEquals("", DashboardPath.normalize("   "))
    @Test fun hostOnlyIsInvalid() = assertNull(DashboardPath.normalize("https://home.glassp.dev/"))
    @Test fun otherSchemeIsInvalid() = assertNull(DashboardPath.normalize("ftp://home/lovelace/x"))
    @Test fun spacesInPathAreInvalid() = assertNull(DashboardPath.normalize("lovelace/my dashboard"))
    @Test fun queryOnlyIsInvalid() = assertNull(DashboardPath.normalize("?kiosk"))

    @Test fun deepLinkAddsServer() = assertEquals("homeassistant://navigate/lovelace/wall?server=default", DashboardPath.deepLink("lovelace/wall"))
    @Test fun deepLinkWithQuery() = assertEquals("homeassistant://navigate/lovelace/wall?kiosk&server=default", DashboardPath.deepLink("https://h/lovelace/wall?kiosk"))
}
