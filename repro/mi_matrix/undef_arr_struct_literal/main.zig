const Client = struct {
    socket: i32,
    active: bool,
};

const Server = struct {
    listen_socket: i32,
    clients: [5]Client,
};

pub fn main() void {
    var server = Server{
        .listen_socket = 3,
        .clients = undefined,
    };
    _ = server;
}
