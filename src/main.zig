const std = @import("std");
const mem = @import("mem");
const stb = @cImport({
    @cDefine("STB_IMAGE_WRITE_IMPLEMENTATION", "1");
    @cDefine("STB_IMAGE_WRITE_STATIC", "1");
    @cInclude("stb_image_write.h");
});

const MAP_SIZE = 256;

const Frequencies = [MAP_SIZE][MAP_SIZE]usize;
const Pixels = [MAP_SIZE][MAP_SIZE]u32;

var frequencies: Frequencies = std.mem.zeroes(Frequencies);
var pixels: Pixels = std.mem.zeroes(Pixels);

fn read_file_to_memory(allocator: std.mem.Allocator, input_path: []const u8) ![]u8 {
    const path = try std.fs.realpathAlloc(allocator, input_path);

    const file = try std.fs.openFileAbsolute(path, .{ .mode = std.fs.File.OpenMode.read_only });
    defer file.close();

    const file_size = (try file.stat()).size;
    const contents = try file.readToEndAlloc(allocator, file_size);

    return contents;
}

const OverlapppingWindowsIterator = struct {
    data: []const u8,
    window_size: usize,
    cursor: usize,

    pub fn next(self: *OverlapppingWindowsIterator) ?[]const u8 {
        if (self.cursor + self.window_size <= self.data.len) {
            const res = self.data[self.cursor .. self.cursor + self.window_size];
            self.cursor += 1;
            return res;
        } else {
            return null;
        }
    }
};

fn overlapping_windows(data: []const u8, window_size: usize) OverlapppingWindowsIterator {
    return OverlapppingWindowsIterator{
        .data = data,
        .window_size = window_size,
        .cursor = 0,
    };
}

fn compute_frequencies(contents: []const u8) void {
    var windows_iter = overlapping_windows(contents, 2);

    while (windows_iter.next()) |window| {
        const x = window[0];
        const y = window[1];
        frequencies[y][x] += 1;
    }
}

fn clear_frequencies() void {
    for (0..MAP_SIZE) |i| {
        for (0..MAP_SIZE) |j| {
            frequencies[i][j] = 0;
        }
    }
}

fn find_max_log_frequency() f32 {
    var max: f32 = 0.0;

    for (frequencies) |row| {
        for (row) |frequency| {
            var log_freq: f32 = 0.0;

            if (frequency > 0) {
                log_freq = @log(@as(f32, @floatFromInt(frequency)));
            }

            if (log_freq > max) {
                max = log_freq;
            }
        }
    }

    return max;
}

fn compute_pixels(max_log_freq: f32) void {
    for (0..frequencies.len) |x| {
        for (0..frequencies[x].len) |y| {
            const frequency = frequencies[x][y];
            var brightness_ratio: f32 = 0.0;

            if (frequency > 0) {
                brightness_ratio = @log(@as(f32, @floatFromInt(frequency))) / max_log_freq;
            }

            const brightness: u32 = @intFromFloat(brightness_ratio * 255);
            pixels[x][y] = 0xFF000000 | brightness | (brightness << 8) | (brightness << 16);
        }
    }
}

fn clear_pixels() void {
    for (0..MAP_SIZE) |i| {
        for (0..MAP_SIZE) |j| {
            pixels[i][j] = 0;
        }
    }
}

fn output_path_from_input_path(allocator: std.mem.Allocator, input_path: [:0]const u8) ![:0]const u8 {
    const res = std.fmt.allocPrintZ(allocator, "{s}.png", .{std.fs.path.basename(input_path)});
    return res;
}

pub fn main() !void {
    var gp = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gp.deinit();
    const allocator = gp.allocator();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Program
    _ = args.next() orelse return;

    var i: usize = 0;
    while (args.next()) |input_path| : (i += 1) {
        const output_path = try output_path_from_input_path(allocator, input_path);
        defer allocator.free(output_path);

        const contents = try read_file_to_memory(arena.allocator(), input_path);

        compute_frequencies(contents);

        const max_log_freq = find_max_log_frequency();

        compute_pixels(max_log_freq);

        const write_res = stb.stbi_write_png(output_path, MAP_SIZE, MAP_SIZE, 4, @ptrCast(&pixels), MAP_SIZE * 4);
        if (write_res != 1) {
            std.debug.print("Failed to write png image for {s}", .{input_path});
        }

        clear_frequencies();
        clear_pixels();
    }

    if (i == 0) {
        return error.NoInputFilesSpecified;
    }
}
