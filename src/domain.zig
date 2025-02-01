pub const General = struct {
    pub const Message = struct { // general message
        sender: []const u8,
        timestamp: i64,
        content: []const u8,
    };
    
    pub const Chat = struct { // general chat
        other: []const u8,

        messages: []Message,
    };
};

pub const JSON = struct {
    pub const SaveData = struct { // save data JSON format
        instance: []const u8,
        token: []const u8,

        chats: []General.Chat,
    };

    pub const Error = struct { // seaorc error JSON format
        err: []const u8,
    };

    pub const Login = struct { // seaorc login JSON format
        username: []const u8,
        password: []const u8,
    };

    pub const Register = Login; // seaorc register JSON format

    pub const Token = struct { // seaorc token response JSON format
        user_token: []const u8,
    };

    pub const Receive = struct {
        messages: []General.Message,
    };

    pub const SendReq = struct {
        receiver: []const u8,
        message: []const u8,
    };

    pub const SendRsp = struct {
        msg_id: i64,
    };
};