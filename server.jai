#import "Basic";
#import "POSIX";
#import "Socket";
#import "Hash_Table";
#import "String";
#import "jason";

#load "battlesnake.jai";

DEBUG_HTTP :: false;
AI_PASSIVE :: 0x0001; // netdb.h
INET6_ADDSTRLEN :: 46;

ports :: string.["4041", "4042", "4043", "4044", "4045", "4046", "4047", "4048", "4049"];
BACKLOG :: 10;
BUFFER_MAX :: 65536;

for_expansion :: (ai: *addrinfo, body: Code, flags: For_Flags) #expand {

    #assert(flags == 0); // we don't support any flags

    `it := ai;
    `it_index := 0;

    while it != null {
        defer { it = it.ai_next; it_index += 1; };
        #insert body;
    }
}

main :: () {

    hints := addrinfo.{
        ai_family   = AF_UNSPEC,
        ai_socktype = SOCK_STREAM,
        ai_flags    = AI_PASSIVE,
    };

    server_info: *addrinfo;
    sockfd : s32;

    yes : s8 = 1;

    success := false;
    for port : ports {

        if getaddrinfo(null, port.data, *hints, *server_info) < 0 {
            print("error getting local addserver_infos info: errno %\n", errno());
            exit(1);
        }

        for server_info {

            sockfd = socket(it.ai_family, it.ai_socktype, it.ai_protocol);
            if sockfd < 0 {
                print("error creating socket to listen on: errno %\n", errno());
                continue;
            }

            if setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, *yes, size_of(type_of(yes))) < -1 {
                print("error setting socket options: errno %\n", errno());
                continue;
            }

            if bind(sockfd, it.ai_addr, it.ai_addrlen) == -1 {
                print("error binding socket to server address %: errno %\n", it.ai_addr, errno());
                continue;
            }

            print("successfully bound to port %\n", port);
            success = true;

            break port;
        }
    }

    if !success {
        write_string("failed to bind\n");
        exit(1);
    }

    freeaddrinfo(server_info);

    if listen(sockfd, BACKLOG) == -1 {
        write_string("error listening on socket\n");
        exit(1);
    }

    sa := sigaction_t.{
        sa_handler = sigchild_handler,
        sa_flags = SA_RESTART,
    };

    if sigaction(SIGCHLD, *sa, null) == -1 {
        write_string("error setting action for SIGCHLD\n");
        exit(1);
    }

    write_string("waiting for connections...\n");

    addr: sockaddr;
    addr_c_str: [INET6_ADDSTRLEN] u8;

    print_req := New(bool);
    while true {

        client_fd, their_addr := accept(sockfd);
        if client_fd == -1 {
            print("error accepting connection from address: %\n", their_addr);
            continue;
        }

        if fork() == 0 { // child

            close(sockfd);

            req : *u8 = alloc(BUFFER_MAX);
            n := read(client_fd, req, BUFFER_MAX);
            if n < 0 {
                print("error reading from socket\n");
                exit(0);
            }

            context.allocator       = __temporary_allocator;
            context.allocator_data  = null;

            request, bytes_parsed, error := parse_request_header(req, cast(u32)n);
            if error != "" {
                print("error parsing HTTP request: %\n", error);
                exit(1);
            }

            /*************************
            * parse the request body *
            *************************/

            {
                // get the content length so we know when we're done parsing the body *
                content_length : s64;

                content_length_str, success := table_find(<<request.headers, "Content-Length");
                if success {
                    content_length, success = string_to_int(content_length_str);
                    if !success {
                        print("error parsing Content-Length header value '%' as int", content_length_str);
                        exit(1);
                    }
                }

                body_builder : String_Builder;
                init_string_builder(*body_builder);

                // put the rest of the unparsed data into the request body
                append(*body_builder, *req[bytes_parsed], n - bytes_parsed);
                while builder_string_length(*body_builder) < content_length { // more data to read from the socket
                    n := read(client_fd, req, cast(u64) (content_length - builder_string_length(*body_builder)));
                    append(*body_builder, req, n);
                }

                request.body = builder_to_string(*body_builder);
                reset(*body_builder);
            }

            free(req);

            response : Response;
            response.headers = New(Table(string, string));

            if request.start_line.method == {

                case .GET;
                    if request.start_line.uri == {

                        case "/";
                            response.body = json_write_string(Battlesnake_Customization.{});

                        case;
                            response.status_line.status_code = 404;
                            response.status_line.reason_phrase = "Not Found";
                    }

                case .POST;
                    if request.start_line.uri == {

                        case "/start";

                        case "/move";
                            game_state, success := json_parse_string(request.body, Battlesnake_Game_State, ignore_unknown=false);
                            if success {
                                response.body = json_write_string(handle_move(game_state));
                            } else {
                                <<print_req = true;
                            }
                            if <<print_req {
                                print("Failed to parse game state from /move POST request\n");
                                print("request.body: %\n", request.body);
                                exit(1);
                            }

                        case "/end";

                        case;
                            response.status_line.status_code = 404;
                            response.status_line.reason_phrase = "Not Found";
                    }

                case .PUT;
                    if request.start_line.uri == {
                        case;
                            response.status_line.status_code = 404;
                            response.status_line.reason_phrase = "Not Found";
                    }

                case .DELETE;
                    if request.start_line.uri == {
                        case;
                            response.status_line.status_code = 404;
                            response.status_line.reason_phrase = "Not Found";
                    }
            }

            res := response_to_string(response);
            sent := write(client_fd, res);
            if sent == -1  print("error sending message to client\n");

            #if DEBUG_HTTP {
                print("request: %\n\n", <<request);
                print("response: %\n", response);

                print("request.start_line: %\n", request.start_line);
                for v, k : request.headers {
                    print("'%': '%'\n", k, v);
                }
                print("body: '%'\n", request.body);
            }

            close(client_fd);
            reset_temporary_storage();
            exit(0);
        }

        reset_temporary_storage();
        close(client_fd);
    }
}

handle_move :: (game_state : Battlesnake_Game_State) -> *Move_Response_Body {

    res : *Move_Response_Body = alloc(size_of(Move_Response_Body));;

    res.move = move_to_string(calculate_move(game_state));
    res.shout = "GOTTA GET THAT BOOM BOOM BOOM";

    return res;
}

sigchild_handler :: (sig: s32) #c_call {
    ctx: Context;
    push_context ctx { // TODO: I don't understand this/know if I can get rid of it
        saved_errno := errno();
        while waitpid(-1, null, WNOHANG) > 0 {}
        set_errno(saved_errno);
    }
}

Move_Response_Body :: struct {
    move  : string;
    shout : string;
}

Response :: struct {
    status_line : Status_Line;
    headers     : *Table(string, string);
    body        : string;
}

Status_Line :: struct {
    http_version  : string = "HTTP/1.1";
    status_code   : int    = 200;
    reason_phrase : string = "OK";
}

response_to_string :: (response : Response) -> string {
    builder : String_Builder;
    init_string_builder(*builder);

    // status line
    append(*builder, tprint("% % %\r\n", response.status_line.http_version, response.status_line.status_code, response.status_line.reason_phrase));

    // headers
    for v, k : response.headers {
        append(*builder, tprint("%: %\r\n", k, v));
    }

    append(*builder, "\r\n");

    // body
    append(*builder, response.body);

    return builder_to_string(*builder);
}

Request :: struct {
    start_line : Start_Line;
    headers    : *Table(string, string);
    body       : string;
}

Start_Line :: struct {
    method  : Method;
    uri     : string;
    version : string;
}

Method :: enum u8 {
    GET;
    POST;
    PUT;
    DELETE;
}

// reference: https://datatracker.ietf.org/doc/html/rfc7230
parse_request_header :: (req : *u8, n : u32) -> *Request, u32, string {

    request : *Request = alloc(size_of(Request));
    i : u32 = 0; // req index

    /*********
    * method *
    *********/

    builder : String_Builder;
    init_string_builder(*builder);

    while is_alpha(req[i]) {
        append(*builder, req[i]);
        i += 1;
        if i == n  return null, 0, "reached end of message while parsing HTTP method";
    }

    method := builder_to_string(*builder);
    if method == {
        case "GET";
            request.start_line.method = .GET;
        case "POST";
            request.start_line.method = .POST;
        case "PUT";
            request.start_line.method = .PUT;
        case "DELETE";
            request.start_line.method = .DELETE;
        case;
            return null, 0, tprint("unexpected HTTP method: %", method);
    }
    reset(*builder);

    // single space
    if req[i] != #char " "  return null, 0, tprint("unexpected character after parsing HTTP method: %", to_string(*req[i], 1));
    i += 1;
    if i == n               return null, 0, "reached end of message after parsing HTTP method";

    /******
    * uri *
    ******/

    while is_http_char(req[i]) {
        append(*builder, req[i]);
        i += 1;
        if i == n  return null, 0, "reached end of message while parsing request URI";
    }

    request.start_line.uri = builder_to_string(*builder);
    reset(*builder);

    // single space
    if req[i] != #char " "  return null, 0, tprint("unexpected character after parsing request URI '%': '%'", request.start_line.uri, to_string(*req[i], 1));
    i += 1;
    if i == n               return null, 0, "reached end of message after parsing request URI";

    /**********
    * version *
    **********/

    while is_http_char(req[i]) {
        append(*builder, req[i]);
        i += 1;
        if i == n  return null, 0, "reached end of message while parsing HTTP version";
    }

    request.start_line.version = builder_to_string(*builder);
    reset(*builder);

    linefeeds, numChars := count_consecutive_linefeeds(req, i, 2);
    i += numChars;
    if linefeeds == {
        case 0;
            return null, 0, tprint("expected (CR)LF at the end of HTTP start-line, got '%'", to_string(*req[i], 1));
        case 1;
            if i == n  return null, 0, "missing (CR)LF after HTTP start-line";
    }

    /**********
    * headers *
    **********/

    request.headers = New(Table(string, string));
    while linefeeds != 2 {

        // field name
        while is_header_field_name_char(req[i]) {
            append(*builder, req[i]);
            i += 1;
            if i == n  return null, 0, "reached end of message while parsing header field name";
        }

        key := builder_to_string(*builder);
        reset(*builder);

        // :
        if req[i] != #char ":"  return null, 0, tprint("unexpected character after parsing header field name '%': expected ':', got '%'", key, to_string(*req[i], 1));
        i += 1;
        if i == n               return null, 0, "reached end of message after parsing header field name";

        // optional whitespace
        while is_hspace(req[i])  i += 1;

        // field value
        while is_header_field_value_char(req[i]) {
            append(*builder, req[i]);
            i += 1;
            if i == n  return null, 0, "reached end of message while parsing header field value";
        }

        table_add(request.headers, key, builder_to_string(*builder));
        reset(*builder);

        // optional whitespace
        while is_hspace(req[i])  i += 1;

        // (CR)LF
        linefeeds, numChars = count_consecutive_linefeeds(req, i, 2);
        i += numChars;
        if linefeeds == {
            case 0;
                return null, 0, tprint("unexpected character after parsing headers. expected (CR)LF, got '%'", to_string(*req[i], 1));
            case 1;
                if i == n  return null, 0, "missing request body";
        }
    }

    return request, i,  "";
}

is_header_field_name_char :: (c : u8) -> bool {
    return is_alnum(c) || c == #char "-";
}

is_header_field_value_char :: (c : u8) -> bool {
    return !is_space(c);
}

is_http_char :: (c : u8) -> bool {
    return is_alnum(c) || c == #char "/" || c == #char ".";
}

is_newline :: (c : u8) -> bool {
    return c == #char "\r" || c == #char "\n";
}

is_hspace :: (c : u8) -> bool {
    return c == #char " " || c == #char "\t";
}

count_consecutive_linefeeds :: (req : *u8, i : u32, max : u32) -> u8, u8 {
    linefeeds : u8 = 0;
    numChars : u8 = 0;

    while 1 {
        if req[i + numChars] == {
            case #char "\r";
                numChars += 1;
            case #char "\n";
                linefeeds += 1;
                numChars += 1;
                if linefeeds < max  continue;
                break;
            case;
                break;
        }
    }
    return linefeeds, numChars;
}
