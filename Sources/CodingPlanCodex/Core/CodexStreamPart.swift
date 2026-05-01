// CodexStreamPart.swift
// CodingPlanCodex
//
// Multi-modal stream event yielded by
// ``OpenAICodexClient/streamResponse(prompt:instructions:model:credentials:tools:)``.

import Foundation

/// One slice of a streaming Codex response. Either a text delta to be
/// appended to the running reply, or an image-lifecycle event from the
/// `image_generation` tool.
public enum CodexStreamPart: Sendable, Equatable {
    /// One streaming text delta. Concatenate every `.textDelta` to
    /// reconstruct the full assistant reply.
    case textDelta(String)
    /// An image-generation lifecycle event — start, progress, partial
    /// preview, or the final completed image. See ``CodexImageEvent``.
    case imageEvent(CodexImageEvent)
}

/// Stages an image generation passes through during a streaming turn.
///
/// On the wire the Codex backend emits `response.image_generation_call.*`
/// events at different points. This enum collapses them into a small
/// surface a chat UI can drive a placeholder + image swap from.
public enum CodexImageEvent: Sendable, Equatable {
    /// Backend acknowledged the image-generation call and queued it.
    /// Show "Starting image generation…" or similar.
    case started(callId: String)
    /// Backend is actively rendering. Drives a shimmering placeholder.
    case generating(callId: String)
    /// A connection keep-alive pulse — no progress, but the server is
    /// still working. Useful for resetting client-side stalled timers.
    case keepalive
    /// A low-fidelity preview of the image arrived. Swap any placeholder
    /// for this PNG; expect a final ``completed(_:)`` shortly after.
    case partial(CodexImage)
    /// The final, fully-rendered image. Replace any partials with this.
    case completed(CodexImage)
}

/// A finished (or partial) image emitted by the `image_generation` tool.
///
/// `pngData` carries decoded PNG bytes ready for
/// `UIImage(data:)` / `NSImage(data:)`.
public struct CodexImage: Sendable, Equatable {
    /// Backend identifier for this generation call (e.g. `"ig_123"`).
    public let id: String
    /// Status reported by the backend. `"completed"` for the final image,
    /// or a transient label like `"generating"` for partial previews.
    public let status: String
    /// The prompt the model used after revision, when the backend reports it.
    public let revisedPrompt: String?
    /// Decoded PNG bytes.
    public let pngData: Data
    /// `true` when this is a partial preview; more frames may follow.
    /// `false` when this is the final image.
    public let isPartial: Bool

    public init(
        id: String,
        status: String,
        revisedPrompt: String? = nil,
        pngData: Data,
        isPartial: Bool = false
    ) {
        self.id = id
        self.status = status
        self.revisedPrompt = revisedPrompt
        self.pngData = pngData
        self.isPartial = isPartial
    }
}
