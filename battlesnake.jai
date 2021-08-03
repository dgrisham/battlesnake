#import "Basic";
#import "Random";
#import "POSIX";

Battlesnake_Game_State :: struct {
    game: Battlesnake_Game;
    turn: u32;
    board: Battlesnake_Board;
    you: Battlesnake_Snake;
}

Battlesnake_Game :: struct {
    id:      string;
    timeout: s64;
    ruleset: struct {
        name: string;
        version: string;
    };
}

Battlesnake_Board :: struct {
    height:  s64;
    width:   s64;
    food:    [..]Coordinate;
    hazards: [..]Coordinate;
    snakes:  [..]Battlesnake_Snake;
}

Board :: struct {

}

Battlesnake_Snake :: struct {
    id:           string;
    name:         string;
    health:       s64;
    body:         []Coordinate;
    latency:      string;
    head:         Coordinate;
    length:       s64;
    shout:        string;
    squad:        string;
    health_delta: s64 = 0;
}

Coordinate :: struct {
    x: int;
    y: int;
}

Snake_Customization :: struct {
    author     : string = "dgrisham";
    color      : string = "#9B3160";
    head       : string = "bender";
    tail       : string = "rbc-necktie";
    version    : string = "0.0.1-beta";
    apiversion : string = "1";
}

operator + :: (c1 : Coordinate, c2 : Coordinate) -> Coordinate {
    c3 : Coordinate;
    c3.x = c1.x + c2.x;
    c3.y = c1.y + c2.y;
    return c3;
}

operator == :: (c1 : Coordinate, c2 : Coordinate) -> bool {
    return c1.x == c2.x && c1.y == c2.y;
}

Move :: enum u8 {
    UP;
    DOWN;
    LEFT;
    RIGHT;
}
NUM_MOVES :: #run type_info(Move).values.count;

move_to_string :: (move : Move) -> string {
    if #complete move == {
        case .UP;
            return "up";
        case .DOWN;
            return "down";
        case .LEFT;
            return "left";
        case .RIGHT;
            return "right";
    }
}

move_snake :: (snake : Battlesnake_Snake, move : Move) -> Battlesnake_Snake {

    new_snake : Battlesnake_Snake;
    new_snake.health_delta = 1;
    new_snake.health       = snake.health - 1;
    new_snake.length       = snake.length;

    body : [..]Coordinate;
    array_reserve(*body, snake.body.count);
    array_add(*body, move_coordinate(snake.body[0], move));

    for i: 1..snake.body.count-1 {
        array_add(*body, snake.body[i-1]);
    }
    new_snake.body = body;
    new_snake.head = new_snake.body[0];

    return new_snake;
}

move_coordinate :: (coord : Coordinate, move : Move) -> Coordinate {
    if #complete move == {
        case .UP;
            return coord + .{x = 0, y = 1};
        case .DOWN;
            return coord + .{x = 0, y = -1};
        case .LEFT;
            return coord + .{x = -1, y = 0};
        case .RIGHT;
            return coord + .{x = 1, y = 0};
    }
}

update_game_state :: (using game_state : Battlesnake_Game_State, you_idx : s64, moves : [..]Move) -> Battlesnake_Game_State {

    new_game_state : Battlesnake_Game_State;

    new_game_state.turn  = turn + 1;
    new_game_state.board = update_board(board, moves);

    return new_game_state;
}

update_board :: (using board : Battlesnake_Board, moves : [..]Move) -> Battlesnake_Board {

    new_board : Battlesnake_Board;

    new_board.height = height;
    new_board.width  = width;

    array_reserve(*new_board.food, food.count);
    for food  array_add(*new_board.food, it);

    array_reserve(*new_board.hazards, hazards.count);
    for hazards  array_add(*new_board.hazards, it);

    array_reserve(*new_board.snakes, snakes.count);
    for move, i : moves {

        updated_snake := move_snake(snakes[i], move);

        j := 0;
        while i < board.food.count - 1 {
            if updated_snake.head == board.food[i] {
                updated_snake.health_delta = 100 - updated_snake.health;
                updated_snake.health = 100;
                array_unordered_remove_by_index(*board.food, i);
            } else {
                i += 1;
            }
        }

        array_add(*new_board.snakes, updated_snake);
    }

    return new_board;
}

HEALTH_THRESHOLD :: 35;
DEAD_SCORE       :: -100;

score_game_state :: (using game_state : Battlesnake_Game_State, you_idx : s64) -> s64 {

    snake_to_score := board.snakes[you_idx];

    // make sure our head is in the board
    if snake_to_score.head.x < 0
    || snake_to_score.head.y < 0
    || snake_to_score.head.x >= board.width
    || snake_to_score.head.y >= board.height {
        return DEAD_SCORE;
    }

    for snake, snakeIdx : board.snakes {
        for snake.body {
            if snakeIdx == you_idx && it_index == 0  continue; // skip our head
            if snake_to_score.head == it  return DEAD_SCORE;
        }
    }

    if snake_to_score.health       <= HEALTH_THRESHOLD       return DEAD_SCORE / 2;
    if snake_to_score.health_delta >= 100 - HEALTH_THRESHOLD return snake_to_score.health_delta;

    return 0;
}

MAX_DEPTH :: 6;

MOVE_LIST :: Move.[.UP, .DOWN, .LEFT, .RIGHT];

Shifted_Battlesnake_Game_State :: struct {
    game_state    : Battlesnake_Game_State;
    move          : Move;
    original_move : Move;
    depth         : s64  = 0;
    dead          : bool = false;
    checked       : bool = false;
}

calculate_move :: (game_state : Battlesnake_Game_State) -> Move {

    you_idx := 0;
    for game_state.board.snakes {
        if game_state.you.id == it.id {
            you_idx = it_index;
            break;
        }
    }

    next_moves : [..]Move;
    bad_moves : [..]Move;
    total_scores := s64.[0, 0, 0, 0];
    num_scores := s64.[0, 0, 0, 0];
    for move, move_idx : MOVE_LIST {

        array_add(*next_moves, move);

        shifted_game_states : [..]Shifted_Battlesnake_Game_State;

        shifted_game_state : Shifted_Battlesnake_Game_State;
        shifted_game_state.move          = move;
        shifted_game_state.original_move = move;
        shifted_game_state.game_state    = update_game_state(game_state, you_idx, next_moves);

        array_add(*shifted_game_states, shifted_game_state);
        array_reset(*next_moves);

        while shifted_game_states.count > 0 {

            for * shifted_game_state : shifted_game_states {

                score := score_game_state(shifted_game_state.game_state, you_idx);
                if score == DEAD_SCORE {
                    shifted_game_state.dead = true;
                    score += shifted_game_state.depth; // prefer to die later
                } else if score > 0 {
                    shifted_game_state.checked = true; // good path, return
                    score -= shifted_game_state.depth; // prefer to get health earlier
                }

                if !state_should_continue(<<shifted_game_state) || shifted_game_state.depth == MAX_DEPTH {
                    total_scores[move_idx] += score;
                    num_scores[move_idx]   += 1;
                }
            }

            prune_game_states(*shifted_game_states); // prune the good + dead ends

            count := shifted_game_states.count - 1;
            for i : 0..count {

                shifted_game_states[i].checked = true; // mark that we've checked this state so it gets pruned
                if shifted_game_states[i].depth == MAX_DEPTH  continue; // state has reached max depth, skip extending to next moves

                for next_move : MOVE_LIST { // extend each remaining valid state to the next move

                    array_add(*next_moves, next_move);

                    shifted_game_state : Shifted_Battlesnake_Game_State;
                    shifted_game_state.move          = next_move;
                    shifted_game_state.original_move = move;
                    shifted_game_state.depth         = shifted_game_states[i].depth + 1;
                    shifted_game_state.game_state    = update_game_state(shifted_game_states[i].game_state, you_idx, next_moves);

                    array_add(*shifted_game_states, shifted_game_state);
                    array_reset(*next_moves);
                }
            }

            prune_game_states(*shifted_game_states);
        }

        array_free(shifted_game_states);
    }

    average_move_scores : [4]s64;
    for total_scores  average_move_scores[it_index] = it / num_scores[it_index];

    max_score := average_move_scores[0];
    max_score_idx := 0;
    for average_move_scores {
        if it_index == 0  continue;
        if it > max_score {
            max_score = it;
            max_score_idx = it_index;
        }
    }

    return cast(Move) max_score_idx;
}

prune_game_states :: inline (game_states: *[..] Shifted_Battlesnake_Game_State) {
    array_filter(game_states, state_should_continue);
}

state_should_continue :: inline (using state : Shifted_Battlesnake_Game_State) -> bool {
    return !checked && !dead;
}

array_filter :: inline (array_pointer: *[..] $T, filter: (T) -> bool) {
    i := 0;
    while i < array_pointer.count {
        array := <<array_pointer;
        if !filter(array[i]) { // element failed filter, remove
            for j : i..array.count-2
                array[j] = array[j+1];
            array_pointer.count -= 1;
        } else { // element passed filter, move on to next
            i += 1;
        }
    }
}
