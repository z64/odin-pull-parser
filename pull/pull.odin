package pull

import "core:strconv"
import "core:encoding/json"

read_string :: proc(p: ^json.Parser) -> (value: string, err: json.Error) {
    tok := p.curr_token
    json.advance_token(p)

    #partial switch tok.kind {
    case .String:
        value, err = json.unquote_string(tok, p.spec, p.allocator)
    case:
        err = .Unexpected_Token
    }

    return value, err
}

read_string_or_null :: proc(p: ^json.Parser) -> (value: Maybe(string), err: json.Error) {
    tok := p.curr_token
    json.advance_token(p)

    #partial switch tok.kind {
    case .String:
        value, err = json.unquote_string(tok, p.spec, p.allocator)
    case .Null:
        value = nil
    case:
        err = .Unexpected_Token
    }

    return value, err
}

read_i64 :: proc(p: ^json.Parser) -> (value: i64, err: json.Error) {
    tok := p.curr_token
    json.advance_token(p)

    #partial switch tok.kind {
    case .Integer:
        value, _ = strconv.parse_i64(tok.text)
    case:
        err = .Unexpected_Token
    }

    return value, err
}

read_i64_or_null :: proc(p: ^json.Parser) -> (value: Maybe(i64), err: json.Error) {
    tok := p.curr_token
    json.advance_token(p)

    #partial switch tok.kind {
    case .Integer:
        value, _ = strconv.parse_i64(tok.text)
    case .Null:
        value = nil
    case:
        err = .Unexpected_Token
    }

    return value, err
}

read_f64 :: proc(p: ^json.Parser) -> (f: f64, err: json.Error) {
    tok := p.curr_token
    json.advance_token(p)

    #partial switch tok.kind {
    case .Float:
        f, _ = strconv.parse_f64(tok.text)
    case:
        err = .Unexpected_Token
    }

    return f, err
}

read_f64_or_null :: proc(p: ^json.Parser) -> (value: Maybe(f64), err: json.Error) {
    tok := p.curr_token
    json.advance_token(p)

    #partial switch tok.kind {
    case .Float:
        value, _ = strconv.parse_f64(tok.text)
    case .Null:
        value = nil
    case:
        err = .Unexpected_Token
    }

    return value, err
}

read_bool :: proc(p: ^json.Parser) -> (value: bool, err: json.Error) {
    tok := p.curr_token
    json.advance_token(p)

    #partial switch tok.kind {
    case .True:
        value = true
    case .False:
        value = false
    case:
        err = .Unexpected_Token
    }

    return value, err
}

read_bool_or_null :: proc(p: ^json.Parser) -> (value: Maybe(bool), err: json.Error) {
    tok := p.curr_token
    json.advance_token(p)

    #partial switch tok.kind {
    case .True:
        value = true
    case .False:
        value = false
    case .Null:
        value = nil
    case:
        err = .Unexpected_Token
    }

    return value, err
}

read_null :: proc(p: ^json.Parser) -> (err: json.Error) {
    tok := p.curr_token
    json.advance_token(p)

    #partial switch tok.kind {
    case .Null:
    case:
        err = .Unexpected_Token
    }

    return err
}

// Overload for conveniently reading a primitive type's canonical JSON token
// into a pointer.
//
// The `or_null` variants correspond to `Maybe(...)`, writing `nil` to the
// pointner if the token is `null`.
//
// If the token does not match, an error will be returned.
//
// This is useful when deserializing into discrete struct fields.
//
// Example:
//
// ```
// Data :: struct {
//     a: int,
//     b: Maybe(string),
//     c: bool,
// }
//
// data: Data
//
// pull.read(&parser, &data.a) // reads an int into `data.a`
// pull.read(&parser, &data.b) // reads a string into `data.b`
// pull.read(&parser, &data.c) // reads a bool into `data.c`
//  ```
read :: proc{
    read_out_string,
    read_out_string_or_null,
    read_out_i64,
    read_out_i64_or_null,
    read_out_f64,
    read_out_f64_or_null,
    read_out_bool,
    read_out_bool_or_null,
}

read_out_string :: proc(p: ^json.Parser, out: ^string) -> (err: json.Error) {
    out^, err = read_string(p)
    return
}

read_out_string_or_null :: proc(p: ^json.Parser, out: ^Maybe(string)) -> (err: json.Error) {
    out^, err = read_string_or_null(p)
    return
}

read_out_i64 :: proc(p: ^json.Parser, out: ^i64) -> (err: json.Error) {
    out^, err = read_i64(p)
    return
}

read_out_i64_or_null :: proc(p: ^json.Parser, out: ^Maybe(i64)) -> (err: json.Error) {
    out^, err = read_i64_or_null(p)
    return
}

read_out_f64 :: proc(p: ^json.Parser, out: ^f64) -> (err: json.Error) {
    out^, err = read_f64(p)
    return
}

read_out_f64_or_null :: proc(p: ^json.Parser, out: ^Maybe(f64)) -> (err: json.Error) {
    out^, err = read_f64_or_null(p)
    return
}

read_out_bool :: proc(p: ^json.Parser, out: ^bool) -> (err: json.Error) {
    out^, err = read_bool(p)
    return
}

read_out_bool_or_null :: proc(p: ^json.Parser, out: ^Maybe(bool)) -> (err: json.Error) {
    out^, err = read_bool_or_null(p)
    return
}

// Creates an `Iterator` struct that can be used with one of the iterator
// procedures.
//
// The iterators will mutate the state of the parser as they consume the object.
//
// If an error occurs while managing the iteration, it will be written to
// `err`. If the iterator enters and encounters a non-`None` error behind this
// pointer, iteration will be aborted.
//
// With each iterator, `i` will be yielded giving the "index" of the iteration.
// This index is not automatically reset if you nest iterators.
//
// You can nest iterator procs that reference the same `Iterator` instance, or
// you can create a new iterator instance to reset the `i` counter. However,
// you should use the same `err` pointer. This allows nested iterators to
// propagate errors outwards.
//
// Example that parses `{"a": "foo", "b": [1,2,3]}`:
//
// ```
// a: string
// b: [dynamic]i64
//
// err: json.Error
// it := pull.make_iterator(&parser, &err)
//
// for key in pull.object_iterator(&it) {
//     swtch key {
//     case "a":
//         pull.read(&parser, &a)
//     case "b":
//         value: i64
//         for _ in pull.array_iterator(&it) {
//             value, err = pull.read_i64(&parser)
//             append(&b, value)
//         }
//     }
// }
// ```
make_iterator :: proc(p: ^json.Parser, err: ^json.Error) -> (it: Iterator) {
    it.p = p
    it.err = err
    return
}

Iterator :: struct {
    p: ^json.Parser,
    err: ^json.Error,
    i: int,
}

// Iterates a JSON object, yielding each key. In the block of your iterator,
// use one of the `read_*` procedures to continue parsing based on this key.
//
// If an error occurs while advancing iteration, it will be written to `it.err`.
// If `it.err` is set to a non-`None` value externally, iteration will abort.
object_iterator :: proc(it: ^Iterator, key_allocator := context.allocator) -> (key: string, i: int, ok: bool) {
    err := it.err^
    // don't continue iteration if we fell into an error state
    if err != .None {
        return "", 0, false
    }

    tok := it.p.curr_token
    #partial switch tok.kind {
    case .Open_Brace:
        // start of object
        json.advance_token(it.p)
        ok = true
    case .Comma:
        // more data
        json.advance_token(it.p)
        ok = true
    case .Close_Brace:
        // end of object
        ok = false
        json.advance_token(it.p)
    case:
        ok = false
        it.err^ = .Unexpected_Token
    }

    if ok {
        key, err = json.parse_object_key(it.p, key_allocator)
        if err != .None {
            it.err^ = err
            ok = false
        }

        err = json.expect_token(it.p, .Colon)
        if err != .None {
            it.err^ = err
            ok = false
        }
    }

    i = it.i
    it.i += 1

    return key, i, ok
}

// Iterates a JSON array, yielding for each object. In the block of your
// iterator, use one of the `read_*` procedures to advance the iteration.
//
// If an error occurs while advancing iteration, it will be written to `it.err`.
// If `it.err` is set to a non-`None` value externally, iteration will abort.
array_iterator :: proc(it: ^Iterator) -> (i: int, ok: bool) {
    err := it.err^
    // don't continue iteration if we fell into an error state
    if err != .None {
        return 0, false
    }

    tok := it.p.curr_token
    #partial switch tok.kind {
    case .Open_Bracket:
        // start of array
        json.advance_token(it.p)
        ok = true
    case .Comma:
        // more data
        json.advance_token(it.p)
        ok = true
    case .Close_Bracket:
        // end of array
        json.advance_token(it.p)
        ok = false
    case:
        it.err^ = .Unexpected_Token
        ok = false
    }

    i = it.i
    it.i += 1

    return i, ok
}

// Skips whatever token the parser is currently on.
//
// This is intended to be used when parsing a struct or array, and you want to
// ignore a field or value, and continue parsing the rest.
//
// If it is on an object, it will skip the entire object.
// If it is on an array, it will skip the entire array.
skip :: proc(p: ^json.Parser) {
    skip_nested :: proc(p: ^json.Parser, open, close: json.Token_Kind) {
        depth := 1
        for depth > 0 {
            tok := p.curr_token

            #partial switch tok.kind {
            case open:  depth += 1
            case close: depth -= 1
            case .EOF:  break
            }

            json.advance_token(p)
        }
    }

    tok := p.curr_token
    #partial switch tok.kind {
    case .Open_Brace: // skip object
        json.advance_token(p)
        skip_nested(p, .Open_Brace, .Close_Brace)
    case .Open_Bracket: // skip array
        json.advance_token(p)
        skip_nested(p, .Open_Bracket, .Close_Bracket)
    case:
        json.advance_token(p)
    }
}
