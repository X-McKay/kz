const std = @import("std");
const provider = @import("../model_provider.zig");

pub const Config = struct {
    provider_config: provider.Config,
    structured_output: provider.StructuredOutput = .json_object,
    supports_tools: bool = false,
    supports_streaming: bool = false,

    pub fn capabilities(self: Config) provider.Capabilities {
        return .{
            .structured_output = self.structured_output,
            .tools = self.supports_tools,
            .streaming = self.supports_streaming,
        };
    }
};

pub const UrlError = error{ InvalidBaseUrl, NoSpaceLeft };

/// Builds the standard Chat Completions URL from an API-root base URL. This is
/// adapter code; alternate providers are free to use different transports.
pub fn chatCompletionsUrl(buffer: []u8, base_url: []const u8) UrlError![]const u8 {
    if (!(std.mem.startsWith(u8, base_url, "https://") or std.mem.startsWith(u8, base_url, "http://"))) {
        return error.InvalidBaseUrl;
    }
    var trimmed = base_url;
    while (trimmed.len > 0 and trimmed[trimmed.len - 1] == '/') trimmed = trimmed[0 .. trimmed.len - 1];
    if (trimmed.len == 0) return error.InvalidBaseUrl;
    return std.fmt.bufPrint(buffer, "{s}/chat/completions", .{trimmed}) catch error.NoSpaceLeft;
}

/// Authentication is optional because local vLLM and compatible gateways may
/// be intentionally unauthenticated. Never synthesize a placeholder secret.
pub fn authorizationValue(buffer: []u8, api_key: ?[]const u8) error{NoSpaceLeft}!?[]const u8 {
    const key = api_key orelse return null;
    if (key.len == 0) return null;
    return std.fmt.bufPrint(buffer, "Bearer {s}", .{key}) catch error.NoSpaceLeft;
}

test "almckay endpoint resolves to Chat Completions path" {
    var buffer: [256]u8 = undefined;
    const url = try chatCompletionsUrl(&buffer, "https://llm.almckay.io/v1/");
    try std.testing.expectEqualStrings("https://llm.almckay.io/v1/chat/completions", url);
}

test "invalid schemes are rejected" {
    var buffer: [256]u8 = undefined;
    try std.testing.expectError(error.InvalidBaseUrl, chatCompletionsUrl(&buffer, "file:///tmp/model"));
}

test "authentication header is absent when key is not configured" {
    var buffer: [256]u8 = undefined;
    try std.testing.expect((try authorizationValue(&buffer, null)) == null);
    try std.testing.expectEqualStrings("Bearer secret", (try authorizationValue(&buffer, "secret")).?);
}
