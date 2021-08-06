#import "Basic";
#import "Random";
#import "POSIX";

Battlesnake_Game_State :: struct {
    game  : Battlesnake_Game;
    turn  : u32;
    board : Battlesnake_Board;
    you   : Battlesnake_Snake;
}

Battlesnake_Game :: struct {
    id      : string;
    timeout : s64;
    ruleset : struct {
        name    : string;
        version : string;
    };
}

Battlesnake_Board :: struct {
    width   : s64;
    height  : s64;
    food    : []Coordinate;
    hazards : []Coordinate;
    snakes  : []Battlesnake_Snake;
}

Battlesnake_Snake :: struct {
    id           : string;
    name         : string;
    health       : s64;
    body         : []Coordinate;
    latency      : string;
    head         : Coordinate;
    length       : s64;
    shout        : string;
    squad        : string;
    health_delta : s64 = 0;
}

Coordinate :: struct {
    x : int;
    y : int;
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

move_battlesnake_snake :: (snake : Battlesnake_Snake, move : Move) -> Battlesnake_Snake {

    new_snake : Battlesnake_Snake;
    new_snake.health_delta = 1;
    new_snake.health       = snake.health - 1;
    new_snake.length       = snake.length;

    new_snake.body    = NewArray(snake.body.count, Coordinate, false);
    new_snake.body[0] = move_coordinate(snake.body[0], move);

    for i: 1..snake.body.count-1 {
        new_snake.body[i] = snake.body[i-1];
    }
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

update_game_state :: (using game_state : *Game_State, moves : []Move) -> *Game_State {

    new_game_state := initialize_game_state(grid.width, grid.height, snakes, self_idx);

    for move, i : moves {

        updated_snake := move_battlesnake_snake(snakes[i], move);
        // TODO: update grid to reflect change in snake (move snake on grid, eat food)

        new_health := snakes[i].health;
        if updated_snake.head.x < 0 || updated_snake.head.x >= grid.width
        || updated_snake.head.y < 0 || updated_snake.head.y >= grid.height
            new_health = 0;
        else if grid.entities[updated_snake.head.x][updated_snake.head.y] == {
            case .FOOD;
                new_health = 100;
            // TODO: these checks don't make sense until we've updated the grid to reflect the moved snakes
            case .SELF; #through;
            case .ENEMY; #through;
            case .ENEMY_HEAD;
                new_health = 0;
        }

        snakes[i].health_delta = new_health - snakes[i].health;
        snakes[i].health       = new_health;

        // j := 0;
        // while j < board.food.count - 1 {
        //     if updated_snake.head == board.food[j] {
        //         updated_snake.health_delta = 100 - updated_snake.health;
        //         updated_snake.health = 100;
        //         array_unordered_remove_by_index(*board.food, j);
        //     } else {
        //         j += 1;
        //     }
        // }

        // new_board.snakes[i] = updated_snake;
    }

    return new_game_state;
}

// update_battlesnake_board :: (using board : Battlesnake_Board, moves : []Move) -> Battlesnake_Board {

//     new_board : Battlesnake_Board;

//     new_board.height = height;
//     new_board.width  = width;

//     array_reserve(*new_board.food, food.count);
//     for food  array_add(*new_board.food, it);

//     array_reserve(*new_board.hazards, hazards.count);
//     for hazards  array_add(*new_board.hazards, it);

//     new_board.snakes = NewArray(moves.count, Battlesnake_Snake);
//     // array_reserve(*new_board.snakes, snakes.count);
//     for move, i : moves {

//         updated_snake := move_snake(snakes[i], move);

//         j := 0;
//         while j < board.food.count - 1 {
//             if updated_snake.head == board.food[j] {
//                 updated_snake.health_delta = 100 - updated_snake.health;
//                 updated_snake.health = 100;
//                 array_unordered_remove_by_index(*board.food, j);
//             } else {
//                 j += 1;
//             }
//         }

//         new_board.snakes[i] = updated_snake;
//     }

//     return new_board;
// }

HEALTH_THRESHOLD :: 35;
DEAD_SCORE       :: -100;

score_game_state :: (using game_state : *Game_State) -> s64 {
    return 0;
}

// score_battlesnake_game_state :: (using game_state : Battlesnake_Game_State, you_idx : s64) -> s64 {

//     snake_to_score := board.snakes[you_idx];

//     // make sure our head is in the board
//     if snake_to_score.head.x < 0
//     || snake_to_score.head.y < 0
//     || snake_to_score.head.x >= board.width
//     || snake_to_score.head.y >= board.height {
//         return DEAD_SCORE;
//     }

//     for snake, snake_idx : board.snakes {
//         for snake.body {
//             if snake_idx == you_idx && it_index == 0  continue; // skip our head
//             if snake_to_score.head == it  return DEAD_SCORE;
//         }
//     }

//     if snake_to_score.health       <= HEALTH_THRESHOLD       return DEAD_SCORE / 2;
//     if snake_to_score.health_delta >= 100 - HEALTH_THRESHOLD return snake_to_score.health_delta;

//     return 0;
// }

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

Shifted_Game_State :: struct {
    game_state    : *Game_State;
    move          : Move;
    original_move : Move;
    depth         : s64  = 0;
    dead          : bool = false;
    checked       : bool = false;
}

Game_State :: struct {
    grid     : Grid;
    snakes   : []Battlesnake_Snake;
    self_idx : s64;
};

Grid :: struct {
    entities : [][]Entity;
    width    : s64;
    height   : s64;
}

Entity :: enum u8 {
    EMPTY;
    SELF_HEAD;
    SELF;
    ENEMY_HEAD;
    ENEMY;
    FOOD;
}

convert_game_state :: (using battlesnake_game_state : *Battlesnake_Game_State) -> *Game_State {

    // determine index of our snake
    you_idx : s64;
    for board.snakes {
        if you.id == it.id {
            you_idx = it_index;
            break;
        }
    }

    using game_state := initialize_game_state(board.width, board.height, board.snakes, you_idx);

    // mark food
    for board.food  grid.entities[grid.height-it.y-1][it.x] = .FOOD;

    return game_state;
}

initialize_game_state :: (width : s64, height : s64, battlesnake_snakes : []Battlesnake_Snake, you_idx : s64) -> *Game_State {

    using game_state := New(Game_State);
    game_state.self_idx = you_idx;

    /******************
    * copy the snakes *
    ******************/

    snakes = NewArray(battlesnake_snakes.count, Battlesnake_Snake, false);
    for battlesnake_snakes  snakes[it_index] = it;

    /******************
    * set up the grid *
    ******************/

    // set grid dimensions
    grid.width  = width;
    grid.height = height;

    // initialize the grid with empty spots
    grid.entities = NewArray(height, []Entity, false);
    for j : 0..height-1 {
        grid.entities[j] = NewArray(width, Entity, false);
        for i : 0..width-1  grid.entities[j][i] = .EMPTY;
    }

    // mark snakes
    for snake, snake_idx : snakes {
        for snake.body {
            if snake_idx == self_idx
                if snake.head == it
                    grid.entities[it.y][it.x] = .SELF_HEAD;
                else
                    grid.entities[it.y][it.x] = .SELF;
            else
                if snake.head == it
                    grid.entities[it.y][it.x] = .ENEMY_HEAD;
                else
                    grid.entities[it.y][it.x] = .ENEMY;
        }
    }

    return game_state;
}

grid_to_string :: (using grid : Grid) -> string {
    builder : String_Builder;
    init_string_builder(*builder);

    for row : entities {
        append(*builder, "[");
        for entity : row {
            if #complete entity == {

                case .EMPTY;
                    append(*builder, "+");
                case .FOOD;
                    append(*builder, "o");

                case .SELF_HEAD;
                    append(*builder, "^");
                case .SELF;
                    append(*builder, "*");

                case .ENEMY_HEAD;
                    append(*builder, "8");
                case .ENEMY;
                    append(*builder, "@");
            }
        }
        append(*builder, "]\n");
    }
    append(*builder, "\n");

    result := builder_to_string(*builder);
    reset(*builder);
    return result;
}

calculate_move :: (battlesnake_game_state : Battlesnake_Game_State) -> Move {

    game_state := convert_game_state(*battlesnake_game_state);

    print(grid_to_string(game_state.grid));

    next_moves : []Move = NewArray(battlesnake_game_state.board.snakes.count, Move);
    total_scores := s64.[0, 0, 0, 0];
    num_scores := s64.[0, 0, 0, 0];
    for move, move_idx : MOVE_LIST {

        next_moves[0] = move;

        shifted_game_states : [..]Shifted_Game_State;

        shifted_game_state : Shifted_Game_State;
        shifted_game_state.move          = move;
        shifted_game_state.original_move = move;
        shifted_game_state.game_state    = update_game_state(game_state, next_moves);

        array_add(*shifted_game_states, shifted_game_state);

        while shifted_game_states.count > 0 {

            for * shifted_game_state : shifted_game_states {

                score := score_game_state(shifted_game_state.game_state);
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

                    next_moves[0] = next_move;

                    shifted_game_state : Shifted_Game_State;
                    shifted_game_state.move          = next_move;
                    shifted_game_state.original_move = move;
                    shifted_game_state.depth         = shifted_game_states[i].depth + 1;
                    shifted_game_state.game_state    = update_game_state(shifted_game_states[i].game_state, next_moves);

                    array_add(*shifted_game_states, shifted_game_state);
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

prune_game_states :: inline (game_states: *[..] Shifted_Game_State) {
    array_filter(game_states, state_should_continue);
}

state_should_continue :: inline (using state : Shifted_Game_State) -> bool {
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
