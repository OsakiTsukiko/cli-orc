const std = @import("std");
const log = std.log;
const fs = std.fs;
const json = std.json;
const fmt = std.fmt;
const mem = std.mem;

const DJSON = @import("./domain.zig").JSON;
const DGeneral = @import("./domain.zig").General;
const Utils = @import("./utils.zig").Utils;

const MessagesGrouped = struct {
    sender: []const u8,
    messages: std.ArrayList(DGeneral.Message),
    old_messages: []DGeneral.Message = &[_]DGeneral.Message{},
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

pub fn in_list(list: []const MessagesGrouped, sender: []const u8) ?usize {
    for (list, 0..) |mg, index| {
        if (mem.eql(u8, mg.sender, sender)) return index;
    }
    return null;
}

pub fn receive_step(_: *std.process.ArgIterator, allocator: std.mem.Allocator, save_file: fs.File) !void {
    const raw_data = try save_file.readToEndAlloc(allocator, 1024 * 1024 * 1024 * 4); 
    // max 4 gb in memory (should be enough for now)
    defer allocator.free(raw_data);
    
    // parse json data // TODO: maybe handle error gracefully?
    const data = try json.parseFromSlice(DJSON.SaveData, allocator, raw_data, .{});
    defer data.deinit();

    const save_data = data.value;

    const instance = save_data.instance;
    const token = save_data.token;

    var body = try receive(allocator, instance, token);
    defer body.deinit();

    const received_messages_j = try json.parseFromSlice(DJSON.Receive, allocator, body.items, .{});
    defer received_messages_j.deinit();

    const received_messages = received_messages_j.value.messages;

    log.info("✉️  Received {d} messages!", .{received_messages.len});

    var msg_grouped_list = std.ArrayList(MessagesGrouped).init(allocator);
    defer msg_grouped_list.deinit();

    defer {
        for (msg_grouped_list.items) |mg| {
            mg.messages.deinit();
        }
    }

    for (0..received_messages.len) |other_index| { // reverse messages (kinda)
        const index = received_messages.len - other_index - 1;
        const message = received_messages[index];

        if (in_list(msg_grouped_list.items, message.sender)) |msg_idx| {
            try msg_grouped_list.items[msg_idx].messages.append(message);
        } else {
            var mg = MessagesGrouped {
                .sender = message.sender,
                .messages = std.ArrayList(DGeneral.Message).init(allocator),       
            };
            try mg.messages.append(message);
            try msg_grouped_list.append(
                mg
            );
        }
    }

    var new_chats: usize = 0;
    for (msg_grouped_list.items, 0..) |mg, i| {
        for (save_data.chats) |chat| {
            if (mem.eql(u8, mg.sender, chat.other)) {
                msg_grouped_list.items[i].old_messages = chat.messages;
                break;
            }
        }
        if (msg_grouped_list.items[i].old_messages.len == 0) { new_chats += 1; }
    }

    for (msg_grouped_list.items) |mg| {
        log.info("🔔 {s}: {d}", .{mg.sender, mg.messages.items.len});
    }

    var new_save_data = DJSON.SaveData {
        .instance = instance,
        .token = token,
        .chats = &[_]DGeneral.Chat{},
    };

    new_save_data.chats = try allocator.alloc(DGeneral.Chat, save_data.chats.len + new_chats);
    defer allocator.free(new_save_data.chats);

    for (save_data.chats, 0..) |old_chat, i| {
        if (in_list(msg_grouped_list.items, old_chat.other)) |mg_i| {
            new_save_data.chats[i] = DGeneral.Chat {
                .other = old_chat.other,
                .messages = msg_grouped_list.items[mg_i].messages.items,
            };
        } else {
            new_save_data.chats[i] = old_chat;
        }
    }

    var i = save_data.chats.len;
    for (msg_grouped_list.items) |mg| {
        if (mg.old_messages.len == 0) {
            new_save_data.chats[i] = DGeneral.Chat {
                .other = mg.sender,
                .messages = mg.messages.items,
            };
            i += 1;
        }
    }

    const new_save_data_str = try json.stringifyAlloc(allocator, new_save_data, .{});
    defer allocator.free(new_save_data_str);
    try save_file.seekTo(0);
    try save_file.writeAll(new_save_data_str);
    try save_file.setEndPos(@as(u64, @intCast(new_save_data_str.len)));
}
