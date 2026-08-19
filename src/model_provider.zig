const std = @import("std");

/// Transport protocols are configuration, not product architecture. Adding a
/// provider implements this interface; it does not change diagnosis or policy.
pub const Protocol = enum {
    openai_compatible,
    anthropic_messages,
    custom,
};

pub const StructuredOutput = enum {
    none,
    json_object,
    json_schema,
};

pub const Capabilities = struct {
    structured_output: StructuredOutput = .none,
    tools: bool = false,
    streaming: bool = false,
};

pub const Config = struct {
    name: []const u8,
    protocol: Protocol,
    base_url: []const u8,
    model_id: []const u8,
    api_key_env: ?[]const u8 = null,
    timeout_ms: u32 = 90_000,
    max_output_tokens: u32 = 2048,

    pub fn validate(self: Config) error{
        MissingName,
        MissingBaseUrl,
        MissingModel,
        InvalidTimeout,
        InvalidOutputLimit,
    }!void {
        if (self.name.len == 0) return error.MissingName;
        if (self.base_url.len == 0) return error.MissingBaseUrl;
        if (self.model_id.len == 0) return error.MissingModel;
        if (self.timeout_ms == 0) return error.InvalidTimeout;
        if (self.max_output_tokens == 0) return error.InvalidOutputLimit;
    }
};

pub const Role = enum { system, user, assistant, tool };

pub const Message = struct {
    role: Role,
    content: []const u8,
};

pub const CompletionRequest = struct {
    messages: []const Message,
    response_format: StructuredOutput = .json_object,
    temperature: f32 = 0,
    max_output_tokens: u32,
};

pub const Usage = struct {
    input_tokens: u64 = 0,
    output_tokens: u64 = 0,
};

pub const CompletionResponse = struct {
    content: []const u8,
    finish_reason: []const u8,
    usage: Usage = .{},
};

/// Provider implementations are injected through a small vtable. The core
/// knows nothing about HTTP paths, headers, SDKs, or provider-specific fields.
pub const Provider = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        complete: *const fn (context: *anyopaque, request: CompletionRequest) anyerror!CompletionResponse,
        capabilities: *const fn (context: *anyopaque) Capabilities,
        modelId: *const fn (context: *anyopaque) []const u8,
    };

    pub fn complete(self: Provider, request: CompletionRequest) !CompletionResponse {
        return self.vtable.complete(self.context, request);
    }

    pub fn capabilities(self: Provider) Capabilities {
        return self.vtable.capabilities(self.context);
    }

    pub fn modelId(self: Provider) []const u8 {
        return self.vtable.modelId(self.context);
    }
};

const Fake = struct {
    calls: u8 = 0,

    fn provider(self: *Fake) Provider {
        return .{ .context = self, .vtable = &vtable };
    }

    fn complete(context: *anyopaque, request: CompletionRequest) anyerror!CompletionResponse {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.calls += 1;
        if (request.messages.len == 0) return error.EmptyMessages;
        return .{ .content = "{}", .finish_reason = "stop" };
    }

    fn capabilities(_: *anyopaque) Capabilities {
        return .{ .structured_output = .json_schema, .tools = true };
    }

    fn modelId(_: *anyopaque) []const u8 {
        return "fixture-model";
    }

    const vtable = Provider.VTable{
        .complete = complete,
        .capabilities = capabilities,
        .modelId = modelId,
    };
};

test "core dispatches through provider-agnostic interface" {
    var fake = Fake{};
    const provider = fake.provider();
    const messages = [_]Message{.{ .role = .user, .content = "diagnose" }};
    const response = try provider.complete(.{ .messages = &messages, .max_output_tokens = 128 });
    try std.testing.expectEqualStrings("{}", response.content);
    try std.testing.expectEqual(@as(u8, 1), fake.calls);
    try std.testing.expectEqual(StructuredOutput.json_schema, provider.capabilities().structured_output);
    try std.testing.expectEqualStrings("fixture-model", provider.modelId());
}

test "provider configuration requires only generic fields" {
    const config = Config{
        .name = "initial",
        .protocol = .openai_compatible,
        .base_url = "https://example.invalid/v1",
        .model_id = "model-a",
    };
    try config.validate();
}
