// OpenAIBackend.swift
// CodingPlanCodex
//
// Shared base URL and originator constants for the ChatGPT backend used by
// the plan-bound OpenAI API clients (Codex, usage, etc.).

import Foundation

/// Shared backend constants for OpenAI plan-bound API clients.
public enum OpenAIBackend {
    /// Production base URL for the ChatGPT backend.
    public static let defaultBaseURL = URL(string: "https://chatgpt.com/backend-api")!

    /// Originator string identifying the Codex CLI to the backend.
    public static let defaultOriginator = "codex_cli_rs"
}
