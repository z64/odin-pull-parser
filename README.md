# odin-pull-parser

This is a set of utility procedures that allow you to interact with
`json.Parser` in a way that emulates a "pull parser". I think in some circles
this is referred to as "immediate mode parsing".

## Pull Parsing

A pull parser incrementally consumes a JSON document by asserting the current
token type, and depositing the parsed value somewhere, until you have completely
parsed the document, an error occurs, or you arbitrarily decide to stop.

As such, it is useful in scenarios where:

- `json.unmarshal` is too much code, you do not want to use reflection, or
  you want to inject more efficient custom behaviors.

- Your native representation is very different from the JSON you are parsing.
  While walking the JSON, you can "route" exactly which JSON fields go onto the
  final parsed type, and perform arbitrary interpretations of the JSON input
  that do not align with the raw JSON text. This is common when, for example,
  a web API gives you a deep nested JSON structure, but you only are interested
  in plucking a few fields onto a flat struct.

- You want to implement a custom validator without marshalling.

## Tips

These are just some notes on how this code could be used:

- You can use a metaprogram to generate a parsing routine given some type
  definitions, or even an example JSON object to make a parser for. I may
  include some examples of this in this repo in the future.

- You can define re-usable fragments of a routine. For example, you might have
  an enum type that many structs share. You could write one routine that parses
  the enum, then call that in `case "enum": parse_my_enum(&parser)`.

## Example

From [`examples/basic.odin`](examples/basic.odin):

```odin
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
```

See also [`pull/test.odin`](pull/test.odin).

## TODO

- Utility for reading unions of primitives that map onto `read_*`
- Benchmark handwritten pull routine against `json.unmarshal`

## References

- [Crystal - JSON::PullParser](https://crystal-lang.org/api/1.6.2/JSON/PullParser.html).
  This is the primary inspiration for these procedures, although this is not an
  exact port - some methods that I have never had a use for have been cut, I
  only ported what I needed & what I thought made the most sense in Odin.
