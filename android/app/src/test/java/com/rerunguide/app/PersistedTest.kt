package com.rerunguide.app

import com.rerunguide.core.*
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test

/** The saved state survives a round trip, and an older build's file keeps the defaults for keys it lacks
 *  (a throw there would wipe every profile and the server link). */
class PersistedTest {
    @Test fun roundTripAndMissingKeys() {
        val p = Persisted(
            profiles = listOf(Profile("p1", "You", "#f0a33a", ThemeID.MIDNIGHT, setOf("genre:Sitcom"), setOf("series:s1"))),
            settings = Settings(crtLines = false, subtitleLanguage = "spa", tuneMode = TuneMode.start, matchContent = true),
            channelEdits = mapOf("genre:Horror" to ChannelEdit(name = "Shock", order = PlayOrder.inOrder, trailerBreaks = false)),
            customChannels = listOf(ChannelDefinition("custom:1", 50, "Columbo", "Marathon", listOf(RuleChip.series("s1", "Columbo")), PlayOrder.inOrder, isCustom = true)),
            selectedLibraryIDs = listOf("1", "2"),
            serverConfig = ServerConfig(ServerKind.plex, "http://10.0.0.2:32400", "Den", addresses = listOf(PlexAddress("http://10.0.0.2:32400", true)), machineID = "m"),
            lastChannelID = "genre:Horror",
            guideFilter = GuideFilter.favorites,
        )
        assertEquals(p, Persisted.fromJson(JSONObject(p.toJson().toString())))

        // A 1.0.4 profile has no favoriteChannelIDs.
        val old = Persisted.fromJson(JSONObject("""{"currentProfileID":"p1","profiles":[{"id":"p1","name":"You","colorHex":"#f0a33a","theme":"late","hiddenChannelIDs":[]}],
            "settings":{"crtLines":false,"subtitleMode":"auto"}}"""))
        assertEquals(Settings(crtLines = false), old.settings)   // "auto" was the old name of "forced"
        assertEquals(Persisted().copy(settings = Settings(crtLines = false)), old)
    }
}
