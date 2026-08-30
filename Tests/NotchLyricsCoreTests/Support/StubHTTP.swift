import Foundation
@testable import NotchLyricsCore

struct StubError: Error, Sendable {}

actor StubHTTP: HTTPFetching {
    private struct Stubbed { let body: Data; let status: Int }
    private var routes: [String: Stubbed] = [:]
    private(set) var requestedURLs: [String] = []
    private var shouldFail = false

    func stub(urlContains key: String, json: String, status: Int = 200) {
        routes[key] = Stubbed(body: Data(json.utf8), status: status)
    }

    func failEverything() { shouldFail = true }

    private func respond(_ url: URL) throws -> (Data, Int) {
        requestedURLs.append(url.absoluteString)
        if shouldFail { throw StubError() }
        // Most specific key wins, so a retry with fewer query items can be
        // stubbed differently from the first attempt.
        for key in routes.keys.sorted(by: { $0.count > $1.count })
        where url.absoluteString.contains(key) {
            return (routes[key]!.body, routes[key]!.status)
        }
        return (Data("{}".utf8), 404)
    }

    func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
        try respond(url)
    }

    func post(_ url: URL, headers: [String: String], body: Data) async throws -> (Data, Int) {
        try respond(url)
    }
}

let sampleQuery = TrackQuery(
    trackID: "spotify:track:3BJe4B8zGnqEdQPMvfVjuS",
    title: "Summertime Sadness", artist: "Lana Del Rey",
    album: "Born To Die", duration: 265.427
)
