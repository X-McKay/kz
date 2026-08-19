const std = @import("std");

pub const Relation = enum {
    ownership,
    selection,
    endpoint,
    ingress_route,
    configuration,
    storage,
    identity,
    scheduling,
};

pub const Edge = struct {
    from_uid: []const u8,
    to_uid: []const u8,
    relation: Relation,
};

pub const Graph = struct {
    edges: []const Edge,

    /// Bounded breadth-first traversal. The caller owns the result buffer, so
    /// queries cannot allocate without an explicit upper bound.
    pub fn related(
        self: Graph,
        start_uid: []const u8,
        relation: ?Relation,
        max_depth: u8,
        output: [][]const u8,
    ) []const []const u8 {
        if (output.len == 0 or max_depth == 0) return output[0..0];
        output[0] = start_uid;
        var len: usize = 1;
        var level_start: usize = 0;
        var depth: u8 = 0;
        while (level_start < len and depth < max_depth) : (depth += 1) {
            const level_end = len;
            for (output[level_start..level_end]) |uid| {
                for (self.edges) |edge| {
                    if (!std.mem.eql(u8, edge.from_uid, uid)) continue;
                    if (relation != null and edge.relation != relation.?) continue;
                    if (contains(output[0..len], edge.to_uid)) continue;
                    if (len == output.len) return output[1..len];
                    output[len] = edge.to_uid;
                    len += 1;
                }
            }
            level_start = level_end;
        }
        return output[1..len];
    }

    pub fn rootOwner(self: Graph, start_uid: []const u8, max_depth: u8) []const u8 {
        var current = start_uid;
        var depth: u8 = 0;
        while (depth < max_depth) : (depth += 1) {
            var parent: ?[]const u8 = null;
            for (self.edges) |edge| {
                if (edge.relation == .ownership and std.mem.eql(u8, edge.to_uid, current)) {
                    parent = edge.from_uid;
                    break;
                }
            }
            if (parent) |uid| current = uid else break;
        }
        return current;
    }
};

fn contains(values: []const []const u8, needle: []const u8) bool {
    for (values) |value| if (std.mem.eql(u8, value, needle)) return true;
    return false;
}

test "root owner follows deployment replica set pod chain" {
    const edges = [_]Edge{
        .{ .from_uid = "deployment", .to_uid = "replicaset", .relation = .ownership },
        .{ .from_uid = "replicaset", .to_uid = "pod", .relation = .ownership },
    };
    try std.testing.expectEqualStrings("deployment", (Graph{ .edges = &edges }).rootOwner("pod", 6));
}

test "traversal respects relation, depth, and caller capacity" {
    const edges = [_]Edge{
        .{ .from_uid = "service", .to_uid = "slice", .relation = .endpoint },
        .{ .from_uid = "slice", .to_uid = "pod-1", .relation = .endpoint },
        .{ .from_uid = "pod-1", .to_uid = "secret", .relation = .configuration },
    };
    var output: [3][]const u8 = undefined;
    const result = (Graph{ .edges = &edges }).related("service", .endpoint, 6, &output);
    try std.testing.expectEqual(@as(usize, 2), result.len);
    try std.testing.expectEqualStrings("slice", result[0]);
    try std.testing.expectEqualStrings("pod-1", result[1]);
}
