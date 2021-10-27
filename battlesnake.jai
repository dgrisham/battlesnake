#import "Basic";
#import "Random";
#import "POSIX";

DEBUG_SNAKE :: false;

/***************************
* battlesnake server types *
***************************/

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
}

Battlesnake_Customization :: struct {
    author     : string = "dgrisham";
    color      : string = "#9B3160";
    head       : string = "bender";
    tail       : string = "rbc-necktie";
    version    : string = "0.0.1-beta";
    apiversion : string = "1";
}

Shifted_Battlesnake_Game_State :: struct {
    game_state    : Battlesnake_Game_State;
    move          : Move;
    original_move : Move;
    depth         : s64  = 0;
    dead          : bool = false;
    checked       : bool = false;
}

/*****************
* internal types *
*****************/

Shifted_Game_State :: struct {
    game_state    : Game_State;
    move          : Move;
    original_move : Move;
    depth         : s64  = 0;
    dead          : bool = false;
    checked       : bool = false;
}

Game_State :: struct {
    grid     : Grid;
    snakes   : []Snake;
    self_idx : s64;
};

Grid :: struct {
    entities : [][]Entity;
    width    : s64;
    height   : s64;
}

Entity :: enum_flags u8 {
    EMPTY;
    HEAD;
    SELF;
    ENEMY;
    FOOD;
}

Snake :: struct {
    health       : s64;
    body         : []Coordinate;
    head         : Coordinate;
    length       : s64;
    health_delta : s64;
    dead         : bool = false;
}

Coordinate :: struct {
    x : int;
    y : int;
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

move_coordinate :: (coord : Coordinate, move : Move) -> Coordinate {
    if #complete move == {
        case .UP;
            return coord + .{x = 0, y = -1};
        case .DOWN;
            return coord + .{x = 0, y = 1};
        case .LEFT;
            return coord + .{x = -1, y = 0};
        case .RIGHT;
            return coord + .{x = 1, y = 0};
    }
}

grid_to_string :: (using grid : Grid) -> string {
    builder : String_Builder;
    init_string_builder(*builder);

    for row : entities {
        append(*builder, "[");
        for entity : row {
            if entity == {

                case .EMPTY;
                    append(*builder, "+");
                case .FOOD;
                    append(*builder, "o");

                case Entity.SELF | .HEAD;
                    append(*builder, "^");
                case .SELF;
                    append(*builder, "*");

                case Entity.ENEMY | .HEAD;
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

/************
* constants *
************/

MAX_DEPTH :: 5;

MAX_HEALTH       :: 100;
HEALTH_THRESHOLD :: 35;
DEAD_SCORE       :: -100;

MOVE_LIST :: Move.[.UP, .DOWN, .LEFT, .RIGHT];

/**********************
* managing game state *
**********************/

// take the game state sent by the battlesnake server and convert to our representation
convert_game_state :: (using battlesnake_game_state : Battlesnake_Game_State) -> Game_State {

    // determine index of our snake
    you_idx : s64;
    for board.snakes {
        if you.id == it.id {
            you_idx = it_index;
            break;
        }
    }

    using game_state := initialize_game_state(board.width, board.height, board.snakes.count, you_idx);

    for battlesnake_snake, snake_idx : board.snakes {

        snakes[snake_idx].health = battlesnake_snake.health;
        snakes[snake_idx].head.x = battlesnake_snake.head.x;
        snakes[snake_idx].head.y = board.height - battlesnake_snake.head.y - 1;
        snakes[snake_idx].length = battlesnake_snake.length;
        snakes[snake_idx].body   = NewArray(battlesnake_snake.body.count, Coordinate, false);

        for battlesnake_snake.body {

            x := it.x;
            y := grid.height - it.y - 1;

            snakes[snake_idx].body[it_index].x = x;
            snakes[snake_idx].body[it_index].y = y;

            if snake_idx == self_idx
                grid.entities[y][x] = .SELF;
            else
                grid.entities[y][x] = .ENEMY;

            if snakes[snake_idx].body[it_index] == snakes[snake_idx].head
                grid.entities[y][x] |= .HEAD;
        }
    }

    // mark food
    for board.food  grid.entities[grid.height-it.y-1][it.x] = .FOOD;

    return game_state;
}

// initialize a new game state with an empty board
initialize_game_state :: (width : s64, height : s64, num_snakes : s64, you_idx : s64) -> Game_State {

    using game_state : Game_State;
    game_state.self_idx = you_idx;

    /******************
    * copy the snakes *
    ******************/

    snakes = NewArray(num_snakes, Snake, false);

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

    return game_state;
}

calculate_move :: (battlesnake_game_state : Battlesnake_Game_State) -> Move {

    game_state := convert_game_state(battlesnake_game_state);

    // if game_state.snakes.count != 1 {
    //     print("game_state.self_idx:\n%\n", game_state.self_idx);
    //     print("grid:\n%\n", grid_to_string(game_state.grid));
    // }

    #if DEBUG_SNAKE  print(grid_to_string(game_state.grid));
    #if DEBUG_SNAKE  print("snakes: %\n", game_state.snakes);

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
    #if DEBUG_SNAKE  for average_move_scores  print("move: %, avg_score: %\n", cast(Move) it_index, it);

    max_score := average_move_scores[0];
    max_score_idx := 0;
    for average_move_scores {
        if it_index == 0  continue;
        if it > max_score {
            max_score = it;
            max_score_idx = it_index;
        }
    }

    #if DEBUG_SNAKE  print("choice: %\n", cast(Move) max_score_idx);

    return cast(Move) max_score_idx;
}

// apply list of moves to every snake in game state, return new game state
update_game_state :: (old : Game_State, moves : []Move) -> Game_State {

    new := initialize_game_state(old.grid.width, old.grid.height, old.snakes.count, old.self_idx);
    for rows, y : old.grid.entities // update food on the board
        for entity, x : rows
            if entity == .FOOD  new.grid.entities[y][x] = .FOOD;

    // for move, i : moves {

    move := moves[0];
    i := old.self_idx;

    // battlesnake removes dead snakes from the board, so this check will only pass if the snake
    // died as we recursed through game states. we don't delete the snake from the array though,
    // so we check the health instead and skip the snake if it's dead
    if old.snakes[i].health != 0 {

        // move the snake
        new.snakes[i] = move_snake(old.snakes[i], move);
        using new.snakes[i];

        // mark snake on grid
        for body {
            if head.x < 0 || head.x >= new.grid.width
            || head.y < 0 || head.y >= new.grid.height { // head is off the board
                health = 0;
                continue;
            } else if new.grid.entities[it.y][it.x] == .FOOD { // TODO: grow snake when it eats
                health = MAX_HEALTH;
            }

            if i == new.self_idx
                new.grid.entities[it.y][it.x] = .SELF;
            else
                new.grid.entities[it.y][it.x] = .ENEMY;

            if head == it
                new.grid.entities[it.y][it.x] |= .HEAD;
        }

    }

    for * new.snakes {

        if it.health != 0 // snake didn't run off board
            if new.grid.entities[it.head.y][it.head.x] == {
                case .SELF;  #through;
                case .ENEMY; #through;
                case Entity.ENEMY | .HEAD;
                    it.health = 0;
            }

        it.health_delta = it.health - old.snakes[it_index].health;
    }

    return new;
}

move_snake :: (snake : Snake, move : Move) -> Snake {

    new_snake : Snake;
    new_snake.health       = snake.health - 1;
    new_snake.length       = snake.length;
    new_snake.health_delta = -1;

    new_snake.body    = NewArray(snake.body.count, Coordinate, false);
    new_snake.body[0] = move_coordinate(snake.body[0], move);
    new_snake.head    = new_snake.body[0];

    for i: 1..snake.body.count-1 {
        if new_snake.head == snake.body[i] && i < snake.body.count-1 {
            // snake ran into its own body
            new_snake.health = 0;
        }
        new_snake.body[i] = snake.body[i-1];
    }

    return new_snake;
}

score_game_state :: (using game_state : Game_State) -> s64 {
    if snakes[self_idx].health == 0                                    return DEAD_SCORE;
    if snakes[self_idx].health <= HEALTH_THRESHOLD                     return DEAD_SCORE / 2;
    if snakes[self_idx].health_delta >= MAX_HEALTH - HEALTH_THRESHOLD  return snakes[self_idx].health_delta;
    return 0;
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
