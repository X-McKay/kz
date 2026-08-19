//! Public kz library surface. The model is deliberately absent from every
//! mutation-capable API: model output must cross schema, policy, freshness,
//! authorization, and dry-run boundaries owned by deterministic code.

pub const types = @import("types.zig");
pub const detectors = @import("detectors.zig");
pub const incidents = @import("incidents.zig");
pub const cache = @import("cache.zig");
pub const graph = @import("graph.zig");
pub const policy = @import("policy.zig");
pub const redaction = @import("redaction.zig");
pub const verification = @import("verification.zig");
pub const model_schema = @import("model_schema.zig");
pub const model_provider = @import("model_provider.zig");
pub const openai_compatible = @import("providers/openai_compatible.zig");
pub const kube = @import("kube/client.zig");

test {
    _ = types;
    _ = detectors;
    _ = incidents;
    _ = cache;
    _ = graph;
    _ = policy;
    _ = redaction;
    _ = verification;
    _ = model_schema;
    _ = model_provider;
    _ = openai_compatible;
    _ = kube;
}
