import XCTest
@testable import RerunGuideCore

/// `HTTP.data` refuses an https → http redirect (the token header would follow it in the clear) and follows any other.
/// Of the refusals only a 401 is a sign-out. With `redirects: false` it follows none: that is how a sign-in first
/// asks a typed address over https (testSignInAsksForHttpsFirst).
final class HTTPRedirectTests: XCTestCase {
    /// https://a.test/up → https://b.test/ok, https://a.test/down → http://b.test/ok; b.test/ok answers "ok". tls.test
    /// answers as a server: Quick Connect's two calls, and /System/Info/Public on every other path; a.test/hop's own
    /// /System/Info/Public only points at it. Records what was asked.
    final class Hops: URLProtocol {
        nonisolated(unsafe) static var seen: [URL] = []
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func stopLoading() {}
        override func startLoading() {
            let url = request.url!
            Self.seen.append(url)
            let hop = ["/up": "https://b.test/ok", "/down": "http://b.test/ok", "/hop/System/Info/Public": "https://tls.test/System/Info/Public"][url.path]
            let tls = ["Enabled": "true", "Initiate": #"{"Code":"123456","Secret":"s"}"#][url.lastPathComponent] ?? #"{"Id":"s1"}"#
            let refused = url.path == "/401-parental" ? ["X-Application-Error-Code": "ParentalControl"] : nil   // Emby's marker
            let response = HTTPURLResponse(url: url, statusCode: hop == nil ? Int(url.lastPathComponent.prefix(3)) ?? 200 : 302, httpVersion: nil,
                                           headerFields: hop.map { ["Location": $0] } ?? refused)!
            if let hop { client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: URL(string: hop)!), redirectResponse: response) }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data((url.host == "tls.test" ? tls : hop == nil ? "ok" : "moved").utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func setUp() { URLProtocol.registerClass(Hops.self); Hops.seen = [] }
    override func tearDown() { URLProtocol.unregisterClass(Hops.self) }

    func get(_ url: String) async throws -> String {
        var r = URLRequest(url: URL(string: url)!)
        r.setValue("secret", forHTTPHeaderField: "X-Plex-Token")
        return String(decoding: try await HTTP.data(r), as: UTF8.self)
    }

    func testHttpsToHttpRedirectIsRefused() async throws {
        do { _ = try await get("https://a.test/down"); XCTFail("followed https → http") }
        catch MediaServerError.http(let code, _) { XCTAssertEqual(code, 302) }
        XCTAssertEqual(Hops.seen.map(\.absoluteString), ["https://a.test/down"])
    }

    /// A 403, or Emby's marked 401, refuses a good token (an access schedule, a proxy): the app must not take it for a
    /// sign-out and drop the link.
    func testOnly401IsUnauthorized() async throws {
        do { _ = try await get("https://a.test/401"); XCTFail("401 passed") }
        catch MediaServerError.unauthorized {}
        do { _ = try await get("https://a.test/403"); XCTFail("403 passed") }
        catch MediaServerError.http(let code, _) { XCTAssertEqual(code, 403) }
        do { _ = try await get("https://a.test/401-parental"); XCTFail("401 passed") }   // Emby, outside an access schedule
        catch MediaServerError.http(let code, _) { XCTAssertEqual(code, 401) }
    }

    /// A typed address has no scheme and is taken as http: the password and the Quick Connect code go over https when
    /// the server itself answers there (tls.test), and to the address as typed when something else does (plain.test)
    /// or when https only points elsewhere (a.test/hop). Nothing else is asked over http.
    func testSignInAsksForHttpsFirst() async throws {
        for typed in ["http://tls.test:8920/jf", "http://plain.test", "http://a.test/hop"] {
            _ = try? await JellyfinClient.login(baseURL: URL(string: typed)!, username: "u", password: "p", deviceID: "d", kind: .jellyfin)
        }
        let qc = try await JellyfinClient.quickConnectStart(baseURL: URL(string: "http://tls.test")!, deviceID: "d")
        XCTAssertEqual(qc.baseURL.absoluteString, "https://tls.test")   // where the app then asks about the code and signs in
        XCTAssertEqual(Hops.seen.map { $0.absoluteString.trimmingCharacters(in: ["?"]) }, [   // the client's empty query
            "https://tls.test:8920/jf/System/Info/Public", "https://tls.test:8920/jf/Users/AuthenticateByName",
            "https://plain.test/System/Info/Public", "http://plain.test/Users/AuthenticateByName",
            "https://a.test/hop/System/Info/Public", "http://a.test/hop/Users/AuthenticateByName",
            "https://tls.test/System/Info/Public", "https://tls.test/QuickConnect/Enabled", "https://tls.test/QuickConnect/Initiate"])
    }

    func testOtherRedirectsAreFollowed() async throws {
        let body = try await get("https://a.test/up")
        XCTAssertEqual(body, "ok")
        XCTAssertEqual(Hops.seen.map(\.absoluteString), ["https://a.test/up", "https://b.test/ok"])
    }
}
