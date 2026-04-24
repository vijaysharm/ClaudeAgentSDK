import Foundation

extension ClawRuntime {

    /// Per-model USD-per-million-tokens pricing.
    public struct ModelPricing: Sendable, Equatable, Codable {
        public var inputCostPerMillion: Double
        public var outputCostPerMillion: Double
        public var cacheCreationCostPerMillion: Double
        public var cacheReadCostPerMillion: Double

        public init(
            inputCostPerMillion: Double,
            outputCostPerMillion: Double,
            cacheCreationCostPerMillion: Double,
            cacheReadCostPerMillion: Double
        ) {
            self.inputCostPerMillion = inputCostPerMillion
            self.outputCostPerMillion = outputCostPerMillion
            self.cacheCreationCostPerMillion = cacheCreationCostPerMillion
            self.cacheReadCostPerMillion = cacheReadCostPerMillion
        }

        public static let defaultSonnetTier = ModelPricing(
            inputCostPerMillion: 15.0,
            outputCostPerMillion: 75.0,
            cacheCreationCostPerMillion: 18.75,
            cacheReadCostPerMillion: 1.5
        )
    }

    public struct TokenUsage: Sendable, Equatable, Codable, Hashable {
        public var inputTokens: UInt32
        public var outputTokens: UInt32
        public var cacheCreationInputTokens: UInt32
        public var cacheReadInputTokens: UInt32

        public init(
            inputTokens: UInt32 = 0, outputTokens: UInt32 = 0,
            cacheCreationInputTokens: UInt32 = 0, cacheReadInputTokens: UInt32 = 0
        ) {
            self.inputTokens = inputTokens
            self.outputTokens = outputTokens
            self.cacheCreationInputTokens = cacheCreationInputTokens
            self.cacheReadInputTokens = cacheReadInputTokens
        }

        public func totalTokens() -> UInt32 {
            inputTokens &+ outputTokens &+ cacheCreationInputTokens &+ cacheReadInputTokens
        }

        public func estimateCostUsd(model: String? = nil) -> Double {
            let pricing = model.flatMap(ClawRuntime.pricingForModel(_:))
                ?? ModelPricing.defaultSonnetTier
            return estimateCostUsd(pricing: pricing).totalCostUsd
        }

        public func estimateCostUsd(pricing: ModelPricing) -> UsageCostEstimate {
            UsageCostEstimate(
                inputCostUsd: Double(inputTokens) / 1_000_000 * pricing.inputCostPerMillion,
                outputCostUsd: Double(outputTokens) / 1_000_000 * pricing.outputCostPerMillion,
                cacheCreationCostUsd: Double(cacheCreationInputTokens) / 1_000_000 * pricing.cacheCreationCostPerMillion,
                cacheReadCostUsd: Double(cacheReadInputTokens) / 1_000_000 * pricing.cacheReadCostPerMillion
            )
        }

        public func summaryLines(label: String, model: String? = nil) -> [String] {
            let usdLabel = ClawRuntime.formatUsd(estimateCostUsd(model: model))
            var header = "\(label): total_tokens=\(totalTokens()) input=\(inputTokens) output=\(outputTokens) cache_write=\(cacheCreationInputTokens) cache_read=\(cacheReadInputTokens) estimated_cost=\(usdLabel)"
            if let m = model { header += " [model=\(m)]" }
            if model == nil || ClawRuntime.pricingForModel(model ?? "") == nil {
                header += " [pricing=estimated-default]"
            }
            let breakdown = estimateCostUsd(
                pricing: model.flatMap(ClawRuntime.pricingForModel(_:)) ?? .defaultSonnetTier
            )
            let bd = "  cost breakdown: input=\(ClawRuntime.formatUsd(breakdown.inputCostUsd)) output=\(ClawRuntime.formatUsd(breakdown.outputCostUsd)) cache_write=\(ClawRuntime.formatUsd(breakdown.cacheCreationCostUsd)) cache_read=\(ClawRuntime.formatUsd(breakdown.cacheReadCostUsd))"
            return [header, bd]
        }
    }

    public struct UsageCostEstimate: Sendable, Equatable, Codable {
        public var inputCostUsd: Double
        public var outputCostUsd: Double
        public var cacheCreationCostUsd: Double
        public var cacheReadCostUsd: Double

        public var totalCostUsd: Double {
            inputCostUsd + outputCostUsd + cacheCreationCostUsd + cacheReadCostUsd
        }
    }

    public struct UsageTracker: Sendable, Equatable {
        public var latestTurn: TokenUsage
        public var cumulative: TokenUsage
        public var turns: UInt32

        public init() {
            self.latestTurn = TokenUsage()
            self.cumulative = TokenUsage()
            self.turns = 0
        }

        public mutating func record(_ u: TokenUsage) {
            self.latestTurn = u
            self.cumulative = TokenUsage(
                inputTokens: cumulative.inputTokens &+ u.inputTokens,
                outputTokens: cumulative.outputTokens &+ u.outputTokens,
                cacheCreationInputTokens: cumulative.cacheCreationInputTokens &+ u.cacheCreationInputTokens,
                cacheReadInputTokens: cumulative.cacheReadInputTokens &+ u.cacheReadInputTokens
            )
            self.turns &+= 1
        }
    }

    // MARK: - Helpers

    public static func pricingForModel(_ model: String) -> ModelPricing? {
        let lower = model.lowercased()
        if lower.contains("haiku") {
            return ModelPricing(
                inputCostPerMillion: 1.0,
                outputCostPerMillion: 5.0,
                cacheCreationCostPerMillion: 1.25,
                cacheReadCostPerMillion: 0.1
            )
        }
        if lower.contains("opus") {
            return ModelPricing(
                inputCostPerMillion: 15.0,
                outputCostPerMillion: 75.0,
                cacheCreationCostPerMillion: 18.75,
                cacheReadCostPerMillion: 1.5
            )
        }
        if lower.contains("sonnet") {
            return .defaultSonnetTier
        }
        return nil
    }

    public static func formatUsd(_ amount: Double) -> String {
        String(format: "$%.4f", amount)
    }
}
