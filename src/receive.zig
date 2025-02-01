const std = @import("std");
const log = std.log;
const fs = std.fs;
const json = std.json;
const fmt = std.fmt;

const DJSON = @import("./domain.zig").JSON;
const DGeneral = @import("./domain.zig").General;
const Utils = @import("./utils.zig").Utils;

const MsgSenderCnt = struct {
    sender: []const u8,
    counter: usize = 0,
};

fn receive(allocator: std.mem.Allocator, instance: []const u8, token: []const u8) !std.ArrayList(u8) {
    // receive http GET function

    // prepare receive url
    const receive_url = try std.fmt.allocPrint(allocator, "{s}/receive", .{instance});
    defer allocator.free(receive_url);

    log.debug("receive url {s}", .{receive_url});

    // turn into uri
    const receive_uri = try std.Uri.parse(receive_url);

    // initialize zig http client
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    // prepare response body (arraylist)
    var body = std.ArrayList(u8).init(allocator);
    // defer body.deinit();

    const token_header = try fmt.allocPrint(allocator, "Bearer {s}", .{token});
    defer allocator.free(token_header);
    
    // make GET request
    const res = try client.fetch(.{
        .location = .{
            .uri = receive_uri,
        },
        .method = .GET,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/json" }, 
            // the server always expects JSON but this looks pretty..
            .{ .name = "Authorization", .value = token_header },
        },
        .response_storage = .{
            .dynamic = &body
        }
    });

    if (res.status == .ok) {
        return body; // only return body if status is successful
    } 

    defer body.deinit(); // early deinit body if status was not successful

    if (res.status == .not_found) { // 404 special case (for now)
        log.err("Error receiving: {s}", .{"Not Found!"}); // log error
        return error.silent; // silently exit (error already logged)
    }
    
    const err = try json.parseFromSlice(DJSON.Error, allocator, body.items, .{}); // parse error
    defer err.deinit();

    log.err("Error receiving: {s}", .{err.value.err}); // log error
    return error.silent; // silently exit (error already logged)
}

pub fn in_list(list: []const MsgSenderCnt, sender: []const u8) bool {
    for (list) |msc| {
        if (std.mem.eql(u8, msc.sender, sender)) return true;
    }
    return false;
}

pub fn receive_step(args: *std.process.ArgIterator, allocator: std.mem.Allocator, save_file: fs.File) !void {
    const raw_data = try save_file.readToEndAlloc(allocator, 1024 * 1024 * 1024 * 4); 
    // max 4 gb in memory (should be enough for now)
    defer allocator.free(raw_data);
    
    // parse json data // TODO: maybe handle error gracefully?
    const data = try json.parseFromSlice(DJSON.SaveData, allocator, raw_data, .{});
    defer data.deinit();

    const instance = data.value.instance;
    const token = data.value.token;

    var body = try receive(allocator, instance, token);
    defer body.deinit();

    const received_messages_j = try json.parseFromSlice(DJSON.Receive, allocator, body.items, .{});
    defer received_messages_j.deinit();

    const received_messages = received_messages_j.value.messages;

    log.info("✉️  Received {d} messages!", .{received_messages.len});

    var msg_by_sender = std.ArrayList(MsgSenderCnt).init(allocator);
    defer msg_by_sender.deinit();

    for (received_messages) |rm| {
        if (in_list(msg_by_sender.items, rm.sender)) {
            for (msg_by_sender.items, 0..) |msc, index| {
                if (std.mem.eql(u8, msc.sender, rm.sender)) {
                    msg_by_sender.items[index].counter += 1;
                    break;
                }
            }
        } else {
            try msg_by_sender.append(
                MsgSenderCnt {
                    .sender = rm.sender,
                    .counter = 1, 
                }
            );
        }
    }

    for (msg_by_sender.items) |msc| {
        log.info("🔔 {s}: {d}", .{msc.sender, msc.counter});
    }

    _ = args;
}
