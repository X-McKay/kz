const std = @import("std");
const types = @import("types.zig");

pub const Entry = struct {
    resource: types.ResourceRef,
    generation: u64 = 0,
    observed_generation: u64 = 0,
};

/// Fixed-capacity cache partition. Production sizing will be configured at
/// startup; reads receive immutable snapshots via a monotonically increasing
/// partition generation.
pub fn Partition(comptime capacity: usize) type {
    return struct {
        const Self = @This();

        entries: [capacity]Entry,
        len: usize = 0,
        generation: u64 = 0,
        resource_version: []const u8 = "",
        synchronized: bool = false,
        stale: bool = true,

        pub fn init() Self {
            // SAFETY: len starts at zero, so entries are never read before upsert initializes them.
            return .{ .entries = undefined };
        }

        pub fn beginRelist(self: *Self) void {
            self.stale = true;
            self.synchronized = false;
            self.len = 0;
        }

        pub fn finishRelist(self: *Self, resource_version: []const u8) void {
            self.resource_version = resource_version;
            self.synchronized = true;
            self.stale = false;
            self.generation += 1;
        }

        pub fn markStale(self: *Self) void {
            self.stale = true;
            self.synchronized = false;
        }

        pub fn upsert(self: *Self, item: Entry) error{CapacityExceeded}!void {
            for (self.entries[0..self.len]) |*existing| {
                if (std.mem.eql(u8, existing.resource.uid, item.resource.uid)) {
                    existing.* = item;
                    self.generation += 1;
                    return;
                }
            }
            if (self.len == capacity) return error.CapacityExceeded;
            self.entries[self.len] = item;
            self.len += 1;
            self.generation += 1;
        }

        pub fn getByUid(self: *const Self, uid: []const u8) ?*const Entry {
            for (self.entries[0..self.len]) |*item| {
                if (std.mem.eql(u8, item.resource.uid, uid)) return item;
            }
            return null;
        }

        pub fn canAuthorizeMutation(self: *const Self) bool {
            return self.synchronized and !self.stale and self.resource_version.len > 0;
        }
    };
}

fn makeEntry(uid: []const u8, version: []const u8) Entry {
    return .{ .resource = .{
        .api_version = "v1",
        .kind = .pod,
        .namespace = "default",
        .name = "pod",
        .uid = uid,
        .resource_version = version,
    } };
}

test "relist atomically gates mutation and replaces partition" {
    var partition = Partition(2).init();
    partition.beginRelist();
    try partition.upsert(makeEntry("pod-1", "1"));
    try std.testing.expect(!partition.canAuthorizeMutation());
    partition.finishRelist("10");
    try std.testing.expect(partition.canAuthorizeMutation());
    partition.markStale();
    try std.testing.expect(!partition.canAuthorizeMutation());
    partition.beginRelist();
    try partition.upsert(makeEntry("pod-2", "11"));
    partition.finishRelist("12");
    try std.testing.expect(partition.getByUid("pod-1") == null);
    try std.testing.expect(partition.getByUid("pod-2") != null);
}

test "cache capacity is bounded" {
    var partition = Partition(1).init();
    try partition.upsert(makeEntry("pod-1", "1"));
    try std.testing.expectError(error.CapacityExceeded, partition.upsert(makeEntry("pod-2", "2")));
}
