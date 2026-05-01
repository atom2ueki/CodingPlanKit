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
    /// resulting image is yielded as ``CodexImageEvent``-wrapped
    /// ``CodexStreamPart/imageEvent(_:)`` events.
    ///
    /// - Parameters:
    ///   - outputFormat: File format (currently only `"png"` is documented).
    ///   - partialImages: How many low-fidelity preview frames the backend
    ///     should stream before the final image. `0` disables previews.
    ///     The Codex backend supports `0...3`; defaults to `2` for a
    ///     visible build-up effect.
    case imageGeneration(outputFormat: String, partialImages: Int)

    /// Convenience: PNG image generation with two preview frames.
    public static let imageGenerationPNG: CodexTool = .imageGeneration(
        outputFormat: "png",
        partialImages: 2
    )
}

extension CodexTool {
    /// Wire JSON object suitable for the Codex `/codex/responses` request body.
    var jsonObject: [String: Any] {
        switch self {
        case .imageGeneration(let outputFormat, let partialImages):
            return [
                "type": "image_generation",
                "output_format": outputFormat,
                "partial_images": partialImages,
            ]
        }
    }
}
