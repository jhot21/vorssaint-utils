// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One shortener lookup chain's network side. The privacy claim lives here:
/// the redirect is declined (`completionHandler(nil)`), so the 3xx response is
/// delivered to `didReceive response` and its `Location` is read from it. The
/// destination is never requested. No body is ever read: the response is
/// cancelled as soon as its headers arrive.
final class URLSessionHopFetcher: NSObject, HopFetching, URLSessionDataDelegate {
    /// Fixed and generic on purpose. It is still a stable fingerprint, and a
    /// shortener may count the request as a click; the settings note says so.
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = LinkUnshortener.defaultBudget
        return configuration
    }

    static func makeRequest(for url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                                 timeoutInterval: LinkUnshortener.defaultBudget)
        request.httpMethod = method
        request.httpShouldHandleCookies = false
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    /// Redirects carry their `Location` resolved against the hop's own URL, so
    /// a relative or protocol-relative value still works.
    static func hopResponse(for response: URLResponse) -> HopResponse {
        guard let http = response as? HTTPURLResponse else { return .failed }
        guard (300...399).contains(http.statusCode), http.statusCode != 304,
              let location = http.value(forHTTPHeaderField: "Location"),
              let target = URL(string: location, relativeTo: http.url)?.absoluteURL else { return .noRedirect }
        return .redirect(target)
    }

    /// Server trust must proceed, or no https lookup could verify its server
    /// and every one would be cancelled. Any credential challenge (Basic,
    /// Digest, NTLM, a client certificate) is cancelled: nothing is sent.
    static func disposition(for challenge: URLAuthenticationChallenge) -> URLSession.AuthChallengeDisposition {
        challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
            ? .performDefaultHandling : .cancelAuthenticationChallenge
    }

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var completion: ((HopResponse) -> Void)?

    func fetch(_ url: URL, method: String, completion: @escaping (HopResponse) -> Void) {
        let session = self.session ?? URLSession(configuration: Self.makeConfiguration(), delegate: self,
                                                 delegateQueue: .main)
        self.session = session
        self.completion = completion
        let task = session.dataTask(with: Self.makeRequest(for: url, method: method))
        self.task = task
        task.resume()
    }

    func cancel() {
        // Dropping the completion breaks the retain cycle with the chain.
        completion = nil
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }

    private func deliver(_ response: HopResponse, from task: URLSessionTask) {
        // A cancelled task reports once more after its headers; only the
        // current task may complete the current fetch.
        guard task === self.task, let completion else { return }
        self.completion = nil
        completion(response)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        completionHandler(.cancel)
        deliver(Self.hopResponse(for: response), from: dataTask)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        deliver(.failed, from: task)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(Self.disposition(for: challenge), nil)
    }
}
