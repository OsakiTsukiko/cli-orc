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

fn send(allocator: std.mem.Allocator, instance: []const u8, token: []const u8, receiver: []const u8, message: []const u8) !std.ArrayList(u8) {
    // send http POST function

    // prepare send url
    const send_url = try std.fmt.allocPrint(allocator, "{s}/send", .{instance});
    defer allocator.free(send_url);

    log.debug("send url {s}", .{send_url});

    // turn into uri
    const send_uri = try std.Uri.parse(send_url);

    // initialize zig http client
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    // prepare response body (arraylist)
    var body = std.ArrayList(u8).init(allocator);
    // defer body.deinit();

    const data = DJSON.SendReq {
        .receiver = receiver,
        .message = message,
    };

    // prepare request body
    const payload = try json.stringifyAlloc(allocator, data, .{});
    defer allocator.free(payload);

    const token_header = try fmt.allocPrint(allocator, "Bearer {s}", .{token});
    defer allocator.free(token_header);
    
    // make POST request
    const res = try client.fetch(.{
        .location = .{
            .uri = send_uri,
        },
        .method = .POST,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/json" }, 
            // the server always expects JSON but this looks pretty..
            .{ .name = "Authorization", .value = token_header },
        },
        .payload = payload,
        .response_storage = .{
            .dynamic = &body
        }
    });

    if (res.status == .ok) {
        return body; // only return body if status is successful
    } 

    defer body.deinit(); // early deinit body if status was not successful

    if (res.status == .not_found) { // 404 special case (for now)
        log.err("Error sending: {s}", .{"Not Found!"}); // log error
        return error.silent; // silently exit (error already logged)
    }
    
    const err = try json.parseFromSlice(DJSON.Error, allocator, body.items, .{}); // parse error
    defer err.deinit();

    log.err("Error sending: {s}", .{err.value.err}); // log error
    return error.silent; // silently exit (error already logged)
}

pub fn in_list(list: []const MessagesGrouped, sender: []const u8) ?usize {
    for (list, 0..) |mg, index| {
        if (mem.eql(u8, mg.sender, sender)) return index;
    }
    return null;
}

pub fn send_step(args: *std.process.ArgIterator, allocator: std.mem.Allocator, save_file: fs.File) !void {
    const raw_data = try save_file.readToEndAlloc(allocator, 1024 * 1024 * 1024 * 4); 
    // max 4 gb in memory (should be enough for now)
    defer allocator.free(raw_data);
    
    // parse json data // TODO: maybe handle error gracefully?
    const data = try json.parseFromSlice(DJSON.SaveData, allocator, raw_data, .{});
    defer data.deinit();

    const save_data = data.value;

    const instance = save_data.instance;
    const token = save_data.token;

    if (args.next()) |receiver| {
        if (args.next()) |message_file_path| {
            const message_file = try fs.cwd().openFile(message_file_path, .{});
            defer message_file.close();

            const message = try message_file.readToEndAlloc(allocator, 1024 * 4);
            defer allocator.free(message);

            var body = try send(allocator, instance, token, receiver, message);
            defer body.deinit();

            const msg_id = try json.parseFromSlice(DJSON.SendRsp, allocator, body.items, .{});
            defer msg_id.deinit();

            log.info("📤  Sent messages (ID: {d})!", .{msg_id.value.msg_id});

            const local_message = DGeneral.Message {
                .sender = "You",
                .timestamp = std.time.timestamp(), // TODO: mayeb sync to server??
                .content = message,
            };

            var chat_index: usize = 0;
            var old_chat: DGeneral.Chat = DGeneral.Chat {
                .other = receiver,
                .messages = &[_]DGeneral.Message{},
            };

            for (save_data.chats, 0..) |chat, i| {
                if (mem.eql(u8, receiver, chat.other)) {
                    old_chat = chat;
                    chat_index = i;
                    break;
                }
            }

            const new_messages = try allocator.alloc(DGeneral.Message, old_chat.messages.len + 1);
            defer allocator.free(new_messages);

            new_messages[0] = local_message;
            @memcpy(new_messages[1..], old_chat.messages);

            const new_chats = if (old_chat.messages.len == 0) try allocator.alloc(DGeneral.Chat, save_data.chats.len + 1) else try allocator.alloc(DGeneral.Chat, save_data.chats.len);
            defer allocator.free(new_chats);
            @memcpy(new_chats[0..save_data.chats.len], save_data.chats);

            if (old_chat.messages.len == 0) {
                new_chats[save_data.chats.len] = DGeneral.Chat {
                    .other = old_chat.other,
                    .messages = new_messages,
                };
            } else {
                for (new_chats, 0..) |chat, i| {
                    if (mem.eql(u8, old_chat.other, chat.other)) {
                        new_chats[i] = DGeneral.Chat {
                            .other = old_chat.other,
                            .messages = new_messages,
                        };
                        break;
                    }
                }
            }

            const new_save_data = DJSON.SaveData {
                .instance = instance,
                .token = token,
                .chats = new_chats,
            };

            const new_save_data_str = try json.stringifyAlloc(allocator, new_save_data, .{});
            defer allocator.free(new_save_data_str);
            try save_file.seekTo(0);
            try save_file.writeAll(new_save_data_str);
            try save_file.setEndPos(@as(u64, @intCast(new_save_data_str.len)));

            return;
        }
    }

    // USAGE
}
