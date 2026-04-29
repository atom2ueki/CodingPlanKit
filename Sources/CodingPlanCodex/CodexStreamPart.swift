// CodexStreamPart.swift
// CodingPlanCodex
//
// Multi-modal stream event yielded by
// ``OpenAICodexClient/streamResponse(prompt:instructions:model:credentials:tools:)``.

import Foundation

/// One slice of a streaming Codex response. Either a text delta to be
/// appended to the running reply, or a fully-generated image artifact.
public enum CodexStreamPart: Sendable, Equatable {
    /// One streaming text delta. Concatenate every `.textDelta` to
    /// reconstruct the full assistant reply.
    case textDelta(String)
    /// A fully-generated image emitted by the `image_generation` tool.
    case generatedImage(CodexImage)
}

/// A finished image generated mid-turn by the `image_generation` tool.
///
/// `pngData` carries the decoded PNG bytes ready for
/// `UIImage(data:)` / `NSImage(data:)`.
public struct CodexImage: Sendable, Equatable {
    /// Backend identifier for this generation call (e.g. `"ig_123"`).
    public let id: String
    /// Status reported by the backend. Typically `"completed"`.
    public let status: String
    /// The prompt the model used after revision, when the backend reports it.
    public let revisedPrompt: String?
    /// Decoded PNG bytes.
    public let pngData: Data

    public init(
        id: String,
        status: String,
        revisedPrompt: String? = nil,
        pngData: Data
    ) {
        self.id = id
        self.status = status
        self.revisedPrompt = revisedPrompt
        self.pngData = pngData
    }
}
