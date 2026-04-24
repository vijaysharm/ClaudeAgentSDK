import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

extension ClawRuntime {

    public struct OAuthConfig: Sendable, Equatable, Codable {
        public var clientId: String
        public var authorizeUrl: String
        public var tokenUrl: String
        public var callbackPort: UInt16?
        public var manualRedirectUrl: String?
        public var scopes: [String]

        public init(
            clientId: String,
            authorizeUrl: String,
            tokenUrl: String,
            callbackPort: UInt16? = nil,
            manualRedirectUrl: String? = nil,
            scopes: [String] = []
        ) {
            self.clientId = clientId
            self.authorizeUrl = authorizeUrl
            self.tokenUrl = tokenUrl
            self.callbackPort = callbackPort
            self.manualRedirectUrl = manualRedirectUrl
            self.scopes = scopes
        }
    }

    public enum PkceChallengeMethod: String, Sendable, Codable, Equatable {
        case s256 = "S256"
    }

    public struct PkceCodePair: Sendable, Equatable {
        public let verifier: String
        public let challenge: String
        public let challengeMethod: PkceChallengeMethod
    }

    public struct OAuthCallbackParams: Sendable, Equatable {
        public var code: String?
        public var state: String?
        public var error: String?
        public var errorDescription: String?
    }

    public struct OAuthAuthorizationRequest: Sendable, Equatable {
        public var authorizeUrl: String
        public var clientId: String
        public var redirectUri: String
        public var scopes: [String]
        public var state: String
        public var codeChallenge: String
        public var codeChallengeMethod: PkceChallengeMethod
        public var extraParams: [String: String]

        public static func fromConfig(
            _ config: OAuthConfig,
            redirectUri: String,
            state: String,
            pkce: PkceCodePair
        ) -> OAuthAuthorizationRequest {
            OAuthAuthorizationRequest(
                authorizeUrl: config.authorizeUrl,
                clientId: config.clientId,
                redirectUri: redirectUri,
                scopes: config.scopes,
                state: state,
                codeChallenge: pkce.challenge,
                codeChallengeMethod: pkce.challengeMethod,
                extraParams: [:]
            )
        }

        public func withExtraParam(_ key: String, _ value: String) -> OAuthAuthorizationRequest {
            var copy = self
            copy.extraParams[key] = value
            return copy
        }

        public func buildURL() -> String {
            var items: [URLQueryItem] = [
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "client_id", value: clientId),
                URLQueryItem(name: "redirect_uri", value: redirectUri),
                URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "code_challenge", value: codeChallenge),
                URLQueryItem(name: "code_challenge_method", value: codeChallengeMethod.rawValue),
            ]
            for (k, v) in extraParams.sorted(by: { $0.key < $1.key }) {
                items.append(URLQueryItem(name: k, value: v))
            }
            var comps = URLComponents(string: authorizeUrl) ?? URLComponents()
            var existing = comps.queryItems ?? []
            existing.append(contentsOf: items)
            comps.queryItems = existing
            return comps.url?.absoluteString ?? authorizeUrl
        }
    }

    public struct OAuthTokenExchangeRequest: Sendable, Equatable {
        public let grantType: String = "authorization_code"
        public var code: String
        public var redirectUri: String
        public var clientId: String
        public var codeVerifier: String
        public var state: String

        public static func fromConfig(
            _ config: OAuthConfig,
            code: String,
            redirectUri: String,
            codeVerifier: String,
            state: String
        ) -> OAuthTokenExchangeRequest {
            OAuthTokenExchangeRequest(
                code: code, redirectUri: redirectUri,
                clientId: config.clientId, codeVerifier: codeVerifier, state: state
            )
        }

        public func formParams() -> [(String, String)] {
            [
                ("client_id", clientId),
                ("code", code),
                ("code_verifier", codeVerifier),
                ("grant_type", grantType),
                ("redirect_uri", redirectUri),
                ("state", state),
            ]
        }
    }

    public struct OAuthRefreshRequest: Sendable, Equatable {
        public let grantType: String = "refresh_token"
        public var refreshToken: String
        public var clientId: String
        public var scopes: [String]

        public static func fromConfig(
            _ config: OAuthConfig, refreshToken: String, scopes: [String]? = nil
        ) -> OAuthRefreshRequest {
            OAuthRefreshRequest(
                refreshToken: refreshToken,
                clientId: config.clientId,
                scopes: scopes ?? config.scopes
            )
        }

        public func formParams() -> [(String, String)] {
            [
                ("client_id", clientId),
                ("grant_type", grantType),
                ("refresh_token", refreshToken),
                ("scope", scopes.joined(separator: " ")),
            ]
        }
    }

    // MARK: - PKCE helpers

    public static func generatePkcePair() -> PkceCodePair {
        let verifier = generateRandomToken(32)
        let challenge = codeChallengeS256(verifier)
        return PkceCodePair(verifier: verifier, challenge: challenge, challengeMethod: .s256)
    }

    public static func generateState() -> String { generateRandomToken(32) }

    public static func codeChallengeS256(_ verifier: String) -> String {
        let bytes = Array(verifier.utf8)
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: bytes)
        return base64URLEncode(Array(digest))
        #else
        // Minimal SHA-256 fallback is out of scope; require CryptoKit.
        return verifier
        #endif
    }

    public static func loopbackRedirectUri(port: UInt16) -> String {
        "http://localhost:\(port)/callback"
    }

    public static func generateRandomToken(_ n: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: n)
        #if canImport(Security)
        if SecRandomCopyBytes(kSecRandomDefault, n, &bytes) == 0 {
            return base64URLEncode(bytes)
        }
        #endif
        for i in 0..<n { bytes[i] = UInt8.random(in: 0...255) }
        return base64URLEncode(bytes)
    }

    public static func base64URLEncode(_ bytes: [UInt8]) -> String {
        let b64 = Data(bytes).base64EncodedString()
        return b64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Callback parsing

    public static func parseOAuthCallbackRequestTarget(_ target: String) -> OAuthCallbackParams? {
        guard let comps = URLComponents(string: target),
              comps.path == "/callback" else { return nil }
        return parseOAuthCallbackQuery(comps.percentEncodedQuery ?? "")
    }

    public static func parseOAuthCallbackQuery(_ query: String) -> OAuthCallbackParams {
        var params = OAuthCallbackParams()
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            let key = parts[0]
            let value = parts.count > 1 ? (parts[1].removingPercentEncoding ?? parts[1]) : ""
            switch key {
            case "code": params.code = value
            case "state": params.state = value
            case "error": params.error = value
            case "error_description": params.errorDescription = value
            default: break
            }
        }
        return params
    }

    // MARK: - Credential file

    public static func credentialsPath() -> String {
        let env = ProcessInfo.processInfo.environment
        if let home = env["CLAUDE_CONFIG_HOME"], !home.isEmpty {
            return (home as NSString).appendingPathComponent("credentials.json")
        }
        if let home = env["HOME"], !home.isEmpty {
            return (home as NSString).appendingPathComponent(".claude/credentials.json")
        }
        return (FileManager.default.currentDirectoryPath as NSString)
            .appendingPathComponent("credentials.json")
    }

    public static func loadOAuthCredentials() -> ClawAPI.OAuthTokenSet? {
        let path = credentialsPath()
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard let oauth = obj["oauth"] as? [String: Any],
              let jsonData = try? JSONSerialization.data(withJSONObject: oauth),
              let token = try? JSONDecoder().decode(ClawAPI.OAuthTokenSet.self, from: jsonData) else {
            return nil
        }
        return token
    }

    public static func saveOAuthCredentials(_ token: ClawAPI.OAuthTokenSet) throws {
        let path = credentialsPath()
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var existing: [String: Any] = [:]
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            existing = obj
        }
        let tokenData = try JSONEncoder().encode(token)
        let tokenObj = try JSONSerialization.jsonObject(with: tokenData)
        existing["oauth"] = tokenObj
        let output = try JSONSerialization.data(
            withJSONObject: existing, options: [.prettyPrinted, .sortedKeys]
        )
        let tmp = path + ".tmp"
        try output.write(to: URL(fileURLWithPath: tmp))
        _ = try? FileManager.default.removeItem(atPath: path)
        try FileManager.default.moveItem(atPath: tmp, toPath: path)
    }

    public static func clearOAuthCredentials() throws {
        let path = credentialsPath()
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              var obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        obj.removeValue(forKey: "oauth")
        let output = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        try output.write(to: URL(fileURLWithPath: path))
    }
}
