const std = @import("std");
const log = std.log;
const fs = std.fs;
const json = std.json;
const fmt = std.fmt;
const mem = std.mem;

const DJSON = @import("./domain.zig").JSON;
const DGeneral = @import("./domain.zig").General;
const Utils = @import("./utils.zig").Utils;

const DEFAULT_MAX_LENGTH: usize = 32;

pub fn show_step(args: *std.process.ArgIterator, allocator: std.mem.Allocator, save_file: fs.File) !void {
    const raw_data = try save_file.readToEndAlloc(allocator, 1024 * 1024 * 1024 * 4); 
    // max 4 gb in memory (should be enough for now)
    defer allocator.free(raw_data);
    
    // parse json data // TODO: maybe handle error gracefully?
    const data = try json.parseFromSlice(DJSON.SaveData, allocator, raw_data, .{});
    defer data.deinit();

    const save_data = data.value;

    const chats = save_data.chats;

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    if (args.next()) |other| {
        const max_length = if (args.next()) |ml| try fmt.parseInt(usize, ml, 10) else DEFAULT_MAX_LENGTH;

        for (chats) |chat| {
            if (mem.eql(u8, other, chat.other)) {
                for (0..@min(max_length, chat.messages.len)) |i| {
                    if (i != 0) {
                        try stdout.print("\n", .{});
                    }
                    const message = chat.messages[i];
                    try stdout.print("<{s}> [{d}]\n", .{message.sender, message.timestamp});
                    try stdout.print("{s}\n", .{message.content});
                }

                try bw.flush();
                return;
            }
        }
        

        // user not found!!
        log.err("No chat with user {s} found!", .{other});
        return;
    } else {
        try stdout.print("+ CHATS +\n", .{});
        for (chats) |chat| {
            try stdout.print("{s}: {d} messasges\n", .{chat.other, chat.messages.len});
        }
        try bw.flush();
    }
}
