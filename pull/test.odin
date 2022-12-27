package pull

import "core:encoding/json"
import "core:testing"
import "core:slice"
import "core:fmt"

@(private)
make_parser :: proc(s: string) -> json.Parser {
    return json.make_parser_from_string(
        data=s,
        parse_integers=true,
    )
}

@(test)
test_read_array :: proc(x: ^testing.T) {
    s := `[1, "foo", ["some", ["nested", "data"]], true]`
    pull := make_parser(s)
    err: json.Error

    a: i64
    b: string
    c: bool

    it := make_iterator(&pull, &err)
    for i in array_iterator(&it) {
        // writing to err will make the iterator - and any iterators that share
        // the err ptr - abort iteration.
        switch i {
        case 0: a, err = read_i64(&pull)
        case 1: b, err = read_string(&pull)
        case 2: skip(&pull)
        case 3: c, err = read_bool(&pull)
        }
    }

    testing.expect_value(x, a, 1)
    testing.expect_value(x, b, "foo")
    testing.expect_value(x, c, true)
}

@(test)
test_read_object :: proc(x: ^testing.T) {
    Data :: struct {
        s: string,
        i: i64,
        f: f64,
        b: bool,
        ms: Maybe(string),
        mi: Maybe(i64),
        mf: Maybe(f64),
        mb: Maybe(bool),
        a: []i64,
    }

    s := `
    {
        "s":"string",
        "i": 123,
        "f": 1.23,
        "b": true,
        "ms": null,
        "mi": null,
        "mf": null,
        "mb": null,
        "a": [1,2,3]
    }
    `

    assert(json.is_valid(transmute([]u8)s), "invalid JSON in test example")
    pull := make_parser(s)

    d: Data
    err: json.Error

    it := make_iterator(&pull, &err)
    for key in object_iterator(&it) {
        // uses read, which will statically pick the right pull
        // procedure based on the pointer destination type.
        switch key {
        case "s":  err = read(&pull, &d.s)
        case "i":  err = read(&pull, &d.i)
        case "f":  err = read(&pull, &d.f)
        case "b":  err = read(&pull, &d.b)
        case "ms": err = read(&pull, &d.ms)
        case "mi": err = read(&pull, &d.mi)
        case "mf": err = read(&pull, &d.mf)
        case "mb": err = read(&pull, &d.mb)
        case "a":
            ints := make([dynamic]i64)
            i: i64

            for _ in array_iterator(&it) {
                i, err = read_i64(&pull)
                append(&ints, i)
            }

            d.a = ints[:]
        case:
            s := fmt.tprintln("unmatched key in test:", key)
            panic(s)
        }
    }

    testing.expect_value(x, err, json.Error.None)
    testing.expect_value(x, d.s, "string")
    testing.expect_value(x, d.i, 123)
    testing.expect_value(x, d.f, 1.23)
    testing.expect_value(x, d.b, true)
    testing.expect(x, slice.equal(d.a, []i64{1, 2, 3}))
}

// testing routine for adding unit tests of all */*_or_null procs
@(test)
test_primitives :: proc(x: ^testing.T) {
    Primitive_Test :: struct($T: typeid) {
        parse_proc:         #type proc(p: ^json.Parser) -> (T, json.Error),
        parse_or_null_proc: #type proc(p: ^json.Parser) -> (Maybe(T), json.Error),
        expectations: []Expect_Set(T),
    }

    Expect_Set :: struct($T: typeid) {
        input:          string,
        expected_value: T,
        expected_err:   json.Error,
    }

    test_primitive :: proc(x: ^testing.T, test: Primitive_Test($T)) {
        zero: T

        for expect in test.expectations {
            // parse_proc returns the expected value & error
            {
                pull := make_parser(expect.input)
                value, err := test.parse_proc(&pull)

                testing.expect_value(x, value, expect.expected_value)
                testing.expect_value(x, err, expect.expected_err)
            }

            // parse_proc should not handle null
            {
                pull := make_parser(`null`)
                value, err := test.parse_proc(&pull)

                testing.expect_value(x, value, zero)
                testing.expect_value(x, err, json.Error.Unexpected_Token)
            }


            // parse_or_null_proc returns the expected value & error,
            // and returns nil if an error occurred
            {
                pull := make_parser(expect.input)
                value, err := test.parse_or_null_proc(&pull)

                if expect.expected_err == .None {
                    testing.expect_value(x, value, expect.expected_value)
                    testing.expect_value(x, err, json.Error.None)
                } else {
                    testing.expect(x, value == nil)
                    testing.expect_value(x, err, expect.expected_err)
                }
            }

        }

        // parse_or_null_proc also handles null
        {
            pull := make_parser(`null`)
            value, err := test.parse_or_null_proc(&pull)

            testing.expect(x, value == nil)
            testing.expect_value(x, err, json.Error.None)
        }
    }

    // example definitions

    strings := Primitive_Test(string) {
        parse_proc         = read_string,
        parse_or_null_proc = read_string_or_null,
        expectations = {
            {`"foo"`, "foo", .None},
            {`123`, "", .Unexpected_Token},
        },
    }

    ints := Primitive_Test(i64) {
        parse_proc         = read_i64,
        parse_or_null_proc = read_i64_or_null,
        expectations = {
            {`123`, 123, .None},
            {`{}`, 0, .Unexpected_Token},
        },
    }

    floats := Primitive_Test(f64) {
        parse_proc         = read_f64,
        parse_or_null_proc = read_f64_or_null,
        expectations = {
            {`1.23`, 1.23, .None},
            {`{}`, 0, .Unexpected_Token},
        },
    }

    bools := Primitive_Test(bool) {
        parse_proc         = read_bool,
        parse_or_null_proc = read_bool_or_null,
        expectations = {
            {`true`, true, .None},
            {`false`, false, .None},
            {`{}`, false, .Unexpected_Token},
        },
    }

    // run tests

    test_primitive(x, strings)
    test_primitive(x, ints)
    test_primitive(x, floats)
    test_primitive(x, bools)

    // null test is special, since "nil" alone isn't a type in odin
    // so it doesn't work with the test harness above
    {
        pull := make_parser(`null`)
        err := read_null(&pull)
        testing.expect_value(x, err, json.Error.None)
    }

    {
        pull := make_parser(`{}`)
        err := read_null(&pull)
        testing.expect_value(x, err, json.Error.Unexpected_Token)
    }
}
