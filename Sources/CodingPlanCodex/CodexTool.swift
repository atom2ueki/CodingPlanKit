// CodexTool.swift
// CodingPlanCodex
//
// Tools the agent can call during a `/codex/responses` turn. Pass them
// to ``OpenAICodexClient/streamResponse(prompt:instructions:model:credentials:tools:)``
// to opt in.

import Foundation

/// A tool the Codex backend can invoke as part of a response.
public enum CodexTool: Sendable, Equatable, Hashable {
    /// Image generation. The model decides when to invoke it; the
    /// resulting image is yielded as ``CodexStreamPart/generatedImage(_:)``.
    /// `outputFormat` is the file format the backend should return
    /// (currently only `"png"` is documented upstream).
    case imageGeneration(outputFormat: String)

    /// Convenience: PNG image generation, the upstream default.
    public static let imageGenerationPNG: CodexTool = .imageGeneration(outputFormat: "png")
}

extension CodexTool {
    /// Wire JSON object suitable for the Codex `/codex/responses` request body.
    var jsonObject: [String: Any] {
        switch self {
        case .imageGeneration(let outputFormat):
            return [
                "type": "image_generation",
                "output_format": outputFormat,
            ]
        }
    }
}
