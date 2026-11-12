package com.rerunguide.core

import com.sun.net.httpserver.HttpExchange
import com.sun.net.httpserver.HttpServer
import com.sun.net.httpserver.HttpsConfigurator
import com.sun.net.httpserver.HttpsServer
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File
import java.net.InetSocketAddress
import java.net.ProtocolException
import java.security.KeyStore
import java.util.Collections
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.KeyManagerFactory
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManagerFactory

/** `HTTP.data` never follows https → http: the token header would go out in the clear. With `followsRedirects` off it
 *  follows none: that is how a sign-in first asks a typed address over https. */
class HTTPRedirectTests {
    /** A TLS server with a throwaway certificate for 127.0.0.1 (made by the test JDK's own keytool, trusted while
     *  `block` runs) and a plain one, both started and without handlers. */
    private fun servers(block: (secure: HttpsServer, plain: HttpServer) -> Unit) {
        val dir = kotlin.io.path.createTempDirectory().toFile()
        val ks = File(dir, "k.p12"); val pass = "test-only".toCharArray()
        val made = ProcessBuilder(File(System.getProperty("java.home"), "bin/keytool").path, "-genkeypair", "-keystore", ks.path,
            "-storetype", "PKCS12", "-storepass", String(pass), "-alias", "k", "-keyalg", "RSA", "-dname", "CN=127.0.0.1",
            "-ext", "SAN=ip:127.0.0.1", "-validity", "1").redirectErrorStream(true).start().waitFor()
        assertTrue("keytool", made == 0)
        val store = KeyStore.getInstance("PKCS12").apply { ks.inputStream().use { load(it, pass) } }
        val ssl = SSLContext.getInstance("TLS").apply {
            init(KeyManagerFactory.getInstance("SunX509").apply { init(store, pass) }.keyManagers,
                 TrustManagerFactory.getInstance("PKIX").apply { init(store) }.trustManagers, null)
        }
        val plain = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0).apply { start() }
        val secure = HttpsServer.create(InetSocketAddress("127.0.0.1", 0), 0).apply { httpsConfigurator = HttpsConfigurator(ssl); start() }
        val trusted = HttpsURLConnection.getDefaultSSLSocketFactory()
        HttpsURLConnection.setDefaultSSLSocketFactory(ssl.socketFactory)
        try { block(secure, plain) } finally {
            HttpsURLConnection.setDefaultSSLSocketFactory(trusted)
            plain.stop(0); secure.stop(0); dir.deleteRecursively()
        }
    }

    @Test fun testHttpsToHttpRedirectIsRefused() = servers { secure, plain ->
        val tokens = Collections.synchronizedList(mutableListOf<String?>())
        plain.createContext("/") { tokens.add(it.requestHeaders.getFirst("X-Plex-Token")); it.sendResponseHeaders(200, -1); it.close() }
        secure.createContext("/") { it.responseHeaders.add("Location", "http://127.0.0.1:${plain.address.port}/"); it.sendResponseHeaders(302, -1); it.close() }
        val req = URLRequest("https://127.0.0.1:${secure.address.port}/").apply { setValue("server-token", forHTTPHeaderField = "X-Plex-Token") }
        try { runBlocking { HTTP.data(req) }; fail("followed the redirect") } catch (_: ProtocolException) {}
        assertTrue(tokens.toString(), tokens.isEmpty())
    }

    /** The https question before a password or a Quick Connect code (Swift's test of the same name, for what only this
     *  port has): https when the server itself answers there, the address as given when https only points elsewhere.
     *  The refused redirect is read to its end, or its socket is never handed back. */
    @Test fun testSignInAsksForHttpsFirst() = servers { secure, _ ->
        fun answer(x: HttpExchange, code: Int, body: String) {
            val b = body.toByteArray(); x.sendResponseHeaders(code, b.size.toLong()); x.responseBody.use { it.write(b) }
        }
        secure.createContext("/") { answer(it, 200, """{"Id":"s1"}""") }
        secure.createContext("/hop") { it.responseHeaders.add("Location", "/System/Info/Public"); answer(it, 302, "moved") }
        val s = "127.0.0.1:${secure.address.port}"
        runBlocking {
            assertEquals("https://$s/jf", JellyfinClient.secureBase("http://$s/jf", "d"))
            assertEquals("http://$s/hop", JellyfinClient.secureBase("http://$s/hop", "d"))
            try { HTTP.data(URLRequest("https://$s/hop").apply { followsRedirects = false }); fail("followed the redirect") }
            catch (e: MediaServerError.http) { assertEquals("moved", e.body) }
        }
    }
}
