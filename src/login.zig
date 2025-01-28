const std = @import("std");
const log = std.log;
const fs = std.fs;
const json = std.json;

const DJSON = @import("./domain.zig").JSON;

fn login(allocator: std.mem.Allocator, instance: []const u8, data: DJSON.Login) !std.ArrayList(u8) {
    const login_url = try std.fmt.allocPrint(allocator, "{s}/login", .{instance});
    defer allocator.free(login_url);

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var body = std.ArrayList(u8).init(allocator);
    // defer body.deinit();

    const payload = try json.stringifyAlloc(allocator, data, .{});
    defer allocator.free(payload);
        
    const res = try client.fetch(.{
        .location = .{
            .url = login_url,
        },
        .method = .POST,
        .payload = payload,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/json" },
        },
        .response_storage = .{
            .dynamic = &body
        }
    });

    if (res.status == .ok) {
        return body;
    } 

    defer body.deinit();
    
    const err = try json.parseFromSlice(DJSON.Error, allocator, body.items, .{});
    defer err.deinit();

    log.err("Error logging in: {s}", .{err.value.err});
    
    return error.silent;
}

pub fn login_step(args: *std.process.ArgIterator, allocator: std.mem.Allocator, instance: []const u8) !void {
    if (args.next()) |filepath| {
        if (args.next()) |username| {
            if (args.next()) |password| {

                const file = try fs.cwd().createFile(filepath, .{}); // TODO: handle errors more gracefully
                defer file.close();

                const res = try login(allocator, instance, DJSON.Login{
                    .username = username,
                    .password = password,
                });
                defer res.deinit();

                const token = try json.parseFromSlice(DJSON.Token, allocator, res.items, .{});
                defer token.deinit();

                const save = DJSON.SaveData {
                    .instance = instance,
                    .token = token.value.user_token,
                };

                const save_json = try json.stringifyAlloc(allocator, save, .{});
                defer allocator.free(save_json);

                try file.writeAll(save_json);

                return;

            }
        }
    }

    log.err("Usage: ...", .{});
}