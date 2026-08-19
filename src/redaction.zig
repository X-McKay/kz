const std = @import("std");

const marker = "[REDACTED]";
const prefixes = [_][]const u8{
    "bearer ",
    "password=",
    "passwd=",
    "token=",
    "secret=",
    "api_key=",
    "apikey=",
};

/// Redacts common credential forms without allocating. Returns NoSpaceLeft
/// rather than returning a partial, potentially sensitive result.
pub fn into(input: []const u8, output: []u8) error{NoSpaceLeft}![]const u8 {
    var input_index: usize = 0;
    var output_index: usize = 0;

    while (input_index < input.len) {
        var matched: ?usize = null;
        for (prefixes) |prefix| {
            if (input_index + prefix.len <= input.len and
                std.ascii.eqlIgnoreCase(input[input_index .. input_index + prefix.len], prefix))
            {
                matched = prefix.len;
                break;
            }
        }

        if (matched) |prefix_len| {
            try append(output, &output_index, input[input_index .. input_index + prefix_len]);
            try append(output, &output_index, marker);
            input_index += prefix_len;
            while (input_index < input.len and !isDelimiter(input[input_index])) : (input_index += 1) {}
        } else {
            if (output_index >= output.len) return error.NoSpaceLeft;
            output[output_index] = input[input_index];
            output_index += 1;
            input_index += 1;
        }
    }
    return output[0..output_index];
}

fn append(output: []u8, index: *usize, value: []const u8) error{NoSpaceLeft}!void {
    if (index.* + value.len > output.len) return error.NoSpaceLeft;
    @memcpy(output[index.* .. index.* + value.len], value);
    index.* += value.len;
}

fn isDelimiter(value: u8) bool {
    return switch (value) {
        ' ', '\t', '\r', '\n', '&', ';', ',', '"', '\'', '}' => true,
        else => false,
    };
}

test "credential canaries do not survive redaction" {
    const input = "password=hunter2 Bearer eyJhbGci secret=cluster-canary";
    var buffer: [256]u8 = undefined;
    const output = try into(input, &buffer);
    try std.testing.expect(std.mem.indexOf(u8, output, "hunter2") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "eyJhbGci") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "cluster-canary") == null);
    try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, output, marker));
}
