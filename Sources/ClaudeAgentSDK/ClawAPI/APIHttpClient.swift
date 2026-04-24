import Foundation

extension ClawAPI {

    /// Proxy configuration that mirrors `api::http_client::ProxyConfig`.
    ///
    /// Precedence rules (to match the Rust source):
    ///   1. ``proxyUrl`` overrides both per-scheme values when set.
    ///   2. Upper-case env vars win over lower-case ones when both exist.
    ///   3. Empty strings are treated as unset.
    public struct ProxyConfig: Sendable, Equatable {
        public var httpProxy: String?
        public var httpsProxy: String?
        public var noProxy: String?
        public var proxyUrl: String?

        public init(
            httpProxy: String? = nil,
            httpsProxy: String? = nil,
            noProxy: String? = nil,
            proxyUrl: String? = nil
        ) {
            self.httpProxy = httpProxy
            self.httpsProxy = httpsProxy
            self.noProxy = noProxy
            self.proxyUrl = proxyUrl
        }

        public var isEmpty: Bool {
            httpProxy == nil && httpsProxy == nil && noProxy == nil && proxyUrl == nil
        }

        /// Build a proxy config from a `[key: value]` environment snapshot.
        /// Upper-case keys take precedence.
        public static func fromEnvironment(
            _ environment: [String: String] = ProcessInfo.processInfo.environment
        ) -> ProxyConfig {
            ProxyConfig(
                httpProxy: firstNonEmpty(["HTTP_PROXY", "http_proxy"], in: environment),
                httpsProxy: firstNonEmpty(["HTTPS_PROXY", "https_proxy"], in: environment),
                noProxy: firstNonEmpty(["NO_PROXY", "no_proxy"], in: environment),
                proxyUrl: nil
            )
        }

        public static func fromProxyUrl(_ url: String) -> ProxyConfig {
            ProxyConfig(proxyUrl: url)
        }

        private static func firstNonEmpty(_ keys: [String], in env: [String: String]) -> String? {
            for key in keys {
                if let v = env[key], !v.isEmpty { return v }
            }
            return nil
        }

        /// Produce a `URLSessionConfiguration` with this proxy config applied.
        /// On Apple platforms we populate `connectionProxyDictionary`; on Linux
        /// (where URLSession ignores that dict) the caller may need to set env
        /// vars manually.
        public func applied(
            to base: URLSessionConfiguration = .ephemeral
        ) -> URLSessionConfiguration {
            let cfg = base.copy() as? URLSessionConfiguration ?? .ephemeral
            var proxyDict: [AnyHashable: Any] = [:]

            let unified = proxyUrl
            let https = unified ?? httpsProxy
            let http = unified ?? httpProxy

            if let https, let components = URLComponents(string: https), let host = components.host {
                proxyDict["HTTPSEnable"] = 1
                proxyDict["HTTPSProxy"] = host
                if let port = components.port { proxyDict["HTTPSPort"] = port }
            }
            if let http, let components = URLComponents(string: http), let host = components.host {
                proxyDict["HTTPEnable"] = 1
                proxyDict["HTTPProxy"] = host
                if let port = components.port { proxyDict["HTTPPort"] = port }
            }
            if !proxyDict.isEmpty {
                cfg.connectionProxyDictionary = proxyDict
            }
            return cfg
        }
    }

    /// Build a shared ``URLSession`` with the given proxy configuration. Falls
    /// back to ``URLSession/shared`` when the config is empty.
    public static func makeHTTPClient(
        proxy: ProxyConfig = .fromEnvironment()
    ) -> URLSession {
        if proxy.isEmpty { return URLSession.shared }
        return URLSession(configuration: proxy.applied())
    }
}
