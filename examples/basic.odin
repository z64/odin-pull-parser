package examples

import "../pull"
import "core:encoding/json"
import "core:fmt"

Data :: struct {
    a: string,
    b: []i64,
}

data_from_json :: proc(s: string) -> (data: Data) {
    parser := json.make_parser_from_string(data=s, parse_integers=true)

    err: json.Error
    it := pull.make_iterator(&parser, &err)

    for key in pull.object_iterator(&it) {
        switch key {
        case "a":
            // read a string directly into the struct field
            err = pull.read(&parser, &data.a)
        case "b":
            // construct an array to be assigned to data.b
            b := make([dynamic]i64)
            value: i64

            for _ in pull.array_iterator(&it) {
                value, err = pull.read_i64(&parser)
                append(&b, value)
            }

            data.b = b[:]
        case:
            // unknown key, ignore value
            pull.skip(&parser)
        }
    }

    assert(err == json.Error.None)
    return data
}

main :: proc() {
    json_str := `{"a": "string", "b": [1, 2, 3]}`
    data := data_from_json(json_str)
    fmt.println(data)
}
